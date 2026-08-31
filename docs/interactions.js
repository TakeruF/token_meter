/*
 * Token Meter — interaction layer.
 *
 * Everything here follows the same three rules:
 *   1. Feedback lands on pointer-down, never on release.
 *   2. Motion is spring-based, so it always starts from the value that is
 *      currently on screen and can be grabbed and reversed mid-flight.
 *   3. A gesture hands its release velocity to the spring, and the landing
 *      point is projected from that velocity — not snapped from where the
 *      finger happened to stop.
 */
(() => {
  "use strict";

  const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

  /* ----------------------------------------------------------------------
   * Spring — critically damped by default. Parameterised the way Apple
   * parameterises them: damping ratio + response (seconds), not mass /
   * stiffness / friction.
   * -------------------------------------------------------------------- */
  class Spring {
    constructor({ value = 0, damping = 1, response = 0.4 } = {}) {
      this.value = value;
      this.target = value;
      this.velocity = 0;
      this.damping = damping;
      this.response = response;
    }

    step(dt) {
      const omega = (2 * Math.PI) / this.response;
      const stiffness = omega * omega;
      const friction = 2 * this.damping * omega;
      // Fixed sub-steps keep the integration stable through a fast flick.
      const steps = Math.max(1, Math.ceil(dt * 240));
      const h = dt / steps;
      for (let i = 0; i < steps; i += 1) {
        const accel = -stiffness * (this.value - this.target) - friction * this.velocity;
        this.velocity += accel * h;
        this.value += this.velocity * h;
      }
    }

    get settled() {
      return Math.abs(this.velocity) < 0.5 && Math.abs(this.value - this.target) < 0.5;
    }

    snap() {
      this.value = this.target;
      this.velocity = 0;
    }
  }

  /* Apple's momentum projection (UIScrollView deceleration), not v²/2a. */
  const projectMomentum = (velocity, decelerationRate = 0.998) =>
    ((velocity / 1000) * decelerationRate) / (1 - decelerationRate);

  /* Progressive resistance past a boundary instead of a hard stop. */
  const rubberband = (overshoot, dimension, constant = 0.55) =>
    (overshoot * dimension * constant) / (dimension + constant * Math.abs(overshoot));

  /* ----------------------------------------------------------------------
   * Press feedback — the instant the pointer goes down.
   * -------------------------------------------------------------------- */
  function setupPressFeedback() {
    let pressed = null;

    const release = () => {
      if (!pressed) return;
      pressed.classList.remove("is-pressing");
      pressed = null;
    };

    document.addEventListener(
      "pointerdown",
      (event) => {
        const target = event.target.closest("[data-press]");
        if (!target) return;
        release();
        pressed = target;
        target.classList.add("is-pressing");
      },
      { passive: true }
    );

    ["pointerup", "pointercancel", "pointerleave", "blur"].forEach((type) => {
      document.addEventListener(type, release, { passive: true, capture: true });
    });
  }

  /* ----------------------------------------------------------------------
   * Scroll edge effect — the nav only materialises once content is under it.
   * -------------------------------------------------------------------- */
  function setupScrollEdge() {
    const sentinel = document.createElement("div");
    sentinel.setAttribute("aria-hidden", "true");
    sentinel.style.cssText =
      "position:absolute;top:0;left:0;width:1px;height:1px;pointer-events:none;";
    document.body.prepend(sentinel);

    if (!("IntersectionObserver" in window)) return;
    new IntersectionObserver(([entry]) => {
      document.body.classList.toggle("is-scrolled", !entry.isIntersecting);
    }).observe(sentinel);
  }

  /* ----------------------------------------------------------------------
   * Scroll reveal.
   * -------------------------------------------------------------------- */
  function setupReveals() {
    const items = document.querySelectorAll(".reveal");
    if (!("IntersectionObserver" in window)) {
      items.forEach((item) => item.classList.add("is-in"));
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-in");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );

    items.forEach((item) => observer.observe(item));
  }

  /* ----------------------------------------------------------------------
   * Promo carousel — 1:1 tracking, velocity handoff, momentum projection,
   * rubber-banded edges, interruptible at any frame.
   * -------------------------------------------------------------------- */
  function setupCarousel(root) {
    const viewport = root.querySelector("[data-carousel-viewport]");
    const track = root.querySelector("[data-carousel-track]");
    const dotsHost = root.querySelector("[data-carousel-dots]");
    const prevButton = root.querySelector("[data-carousel-prev]");
    const nextButton = root.querySelector("[data-carousel-next]");
    if (!viewport || !track) return;

    const slides = Array.from(track.children);
    if (slides.length < 2) return;

    root.classList.add("is-carousel");
    root.setAttribute("role", "group");
    root.setAttribute("aria-roledescription", "carousel");
    viewport.tabIndex = 0;

    const spring = new Spring({ damping: 1, response: 0.4 });
    let index = 0;
    let step = 0;
    let frame = 0;
    let lastFrameTime = 0;
    let running = false;
    let dragging = false;
    let axis = null;
    let activePointer = null;
    let startX = 0;
    let startY = 0;
    let base = 0;
    let dragStartIndex = 0;
    let wheelTimer = 0;
    const history = [];

    const minValue = () => -(slides.length - 1) * step;
    const reduced = () => motionQuery.matches;

    const dots = slides.map((slide, i) => {
      slide.setAttribute("role", "group");
      slide.setAttribute("aria-roledescription", "slide");
      slide.setAttribute("aria-label", `${i + 1} / ${slides.length}`);

      const dot = document.createElement("button");
      dot.type = "button";
      dot.className = "promo-dot";
      dot.dataset.press = "";
      dot.setAttribute("aria-label", `${i + 1} / ${slides.length}`);
      dot.addEventListener("click", () => goTo(i));
      if (dotsHost) dotsHost.append(dot);
      return dot;
    });

    function render() {
      track.style.transform = `translate3d(${spring.value.toFixed(2)}px, 0, 0)`;
      if (reduced() || step === 0) return;
      // Neighbours sit slightly back, so a partial drag already telegraphs
      // which slide is arriving.
      const center = -spring.value / step;
      slides.forEach((slide, i) => {
        const distance = Math.min(1, Math.abs(i - center));
        slide.style.transform = `scale(${(1 - 0.05 * distance).toFixed(4)})`;
        slide.style.opacity = (1 - 0.4 * distance).toFixed(3);
      });
    }

    function tick(now) {
      const dt = clamp((now - lastFrameTime) / 1000, 0.001, 0.032);
      lastFrameTime = now;
      spring.step(dt);
      render();
      if (spring.settled) {
        spring.snap();
        render();
        running = false;
        track.style.willChange = "";
        return;
      }
      frame = requestAnimationFrame(tick);
    }

    function startLoop() {
      if (running) return;
      running = true;
      track.style.willChange = "transform";
      lastFrameTime = performance.now();
      frame = requestAnimationFrame(tick);
    }

    function stopLoop() {
      cancelAnimationFrame(frame);
      running = false;
    }

    function updateControls() {
      dots.forEach((dot, i) => {
        if (i === index) dot.setAttribute("aria-current", "true");
        else dot.removeAttribute("aria-current");
      });
      if (prevButton) prevButton.disabled = index === 0;
      if (nextButton) nextButton.disabled = index === slides.length - 1;
    }

    function goTo(next, velocity = 0) {
      index = clamp(next, 0, slides.length - 1);
      spring.target = -index * step;
      spring.velocity = velocity;
      // Overshoot is earned by momentum: a flick bounces, a tap does not.
      spring.damping = Math.abs(velocity) > 300 ? 0.8 : 1;
      spring.response = reduced() ? 0.15 : 0.4;
      updateControls();
      startLoop();
    }

    function measure() {
      const gap = parseFloat(getComputedStyle(track).columnGap) || 0;
      // The viewport is never transformed; a slide's own scale would skew its rect.
      const width = viewport.getBoundingClientRect().width;
      if (!width) return;
      step = width + gap;
      if (dragging) return;
      stopLoop();
      spring.target = -index * step;
      spring.snap();
      render();
    }

    function constrain(value) {
      const max = 0;
      const min = minValue();
      const width = viewport.getBoundingClientRect().width || 1;
      if (value > max) return max + rubberband(value - max, width);
      if (value < min) return min - rubberband(min - value, width);
      return value;
    }

    viewport.addEventListener("dragstart", (event) => event.preventDefault());

    viewport.addEventListener(
      "pointerdown",
      (event) => {
        if (event.pointerType === "mouse" && event.button !== 0) return;
        activePointer = event.pointerId;
        axis = null;
        startX = event.clientX;
        startY = event.clientY;
        // Grab the presentation value, so an in-flight slide is caught
        // exactly where it is rather than jumping to its target.
        stopLoop();
        base = spring.value;
        dragStartIndex = index;
        spring.velocity = 0;
        history.length = 0;
        history.push({ x: event.clientX, t: event.timeStamp });
      },
      { passive: true }
    );

    viewport.addEventListener(
      "pointermove",
      (event) => {
        if (event.pointerId !== activePointer) return;
        const dx = event.clientX - startX;
        const dy = event.clientY - startY;

        if (!axis) {
          if (Math.hypot(dx, dy) < 10) return; // hysteresis before committing
          if (Math.abs(dy) > Math.abs(dx)) {
            activePointer = null; // vertical intent: leave the page alone
            return;
          }
          axis = "x";
          dragging = true;
          base -= dx; // absorb the hysteresis so tracking stays 1:1
          viewport.classList.add("is-dragging");
          if (viewport.setPointerCapture) viewport.setPointerCapture(event.pointerId);
          track.style.willChange = "transform";
        }

        history.push({ x: event.clientX, t: event.timeStamp });
        if (history.length > 6) history.shift();

        spring.value = constrain(base + dx);
        render();
      },
      { passive: true }
    );

    function endDrag(event) {
      if (event.pointerId !== activePointer) return;
      activePointer = null;
      if (!dragging) return;
      dragging = false;
      viewport.classList.remove("is-dragging");

      let velocity = 0;
      const recent = history.filter((point) => event.timeStamp - point.t < 120);
      if (recent.length > 1) {
        const first = recent[0];
        const last = recent[recent.length - 1];
        const dt = (last.t - first.t) / 1000;
        if (dt > 0) velocity = (last.x - first.x) / dt;
      }

      // Land where the gesture was going, then hand the velocity over.
      const projected = Math.round(-(spring.value + projectMomentum(velocity)) / step);
      let target = Math.round(-spring.value / step);
      if (Math.abs(velocity) > 400) {
        // A deliberate flick commits in the direction it was thrown, even if it
        // was short: the sign of the velocity decides, not where the finger
        // stopped. Momentum can still carry it further than one slide.
        const flicked = dragStartIndex + (velocity < 0 ? 1 : -1);
        target = velocity < 0 ? Math.max(flicked, projected) : Math.min(flicked, projected);
      } else {
        target = projected;
      }
      goTo(target, velocity);
    }

    viewport.addEventListener("pointerup", endDrag, { passive: true });
    viewport.addEventListener("pointercancel", endDrag, { passive: true });

    // Trackpad: a two-finger horizontal swipe is the same gesture.
    viewport.addEventListener(
      "wheel",
      (event) => {
        if (Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
        event.preventDefault();
        stopLoop();
        spring.value = constrain(spring.value - event.deltaX);
        spring.velocity = 0;
        render();
        clearTimeout(wheelTimer);
        wheelTimer = window.setTimeout(() => {
          goTo(Math.round(-spring.value / step));
        }, 110);
      },
      { passive: false }
    );

    viewport.addEventListener("keydown", (event) => {
      if (event.key === "ArrowLeft") {
        event.preventDefault();
        goTo(index - 1);
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        goTo(index + 1);
      }
    });

    if (prevButton) prevButton.addEventListener("click", () => goTo(index - 1));
    if (nextButton) nextButton.addEventListener("click", () => goTo(index + 1));

    if ("ResizeObserver" in window) {
      new ResizeObserver(measure).observe(viewport);
    } else {
      window.addEventListener("resize", measure);
    }
    window.addEventListener("load", measure);
    motionQuery.addEventListener?.("change", () => {
      slides.forEach((slide) => {
        slide.style.transform = "";
        slide.style.opacity = "";
      });
      render();
    });

    measure();
    updateControls();
  }

  function init() {
    setupPressFeedback();
    setupScrollEdge();
    setupReveals();
    document.querySelectorAll("[data-carousel]").forEach(setupCarousel);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

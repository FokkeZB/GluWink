// Tiny dependency-free carousel for the hero phone.
// - Auto-advances every data-interval ms (default 5000)
// - Pauses on hover, focus-within, and when the tab is hidden
// - Manual control via dot buttons, ArrowLeft/ArrowRight when focused
// - Honors prefers-reduced-motion (no auto-advance, no fade)
(function () {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  document.querySelectorAll('[data-carousel]').forEach(setup);

  function setup(root) {
    const slides = Array.from(root.querySelectorAll('[data-slide]'));
    const dots = Array.from(root.querySelectorAll('[data-slide-to]'));
    if (slides.length < 2) return;

    const intervalMs = parseInt(root.dataset.interval, 10) || 5000;
    let index = 0;
    let timer = null;

    // Hydrate a slide's <img data-src=...> into a real <img src=...> the
    // first time we need it. Slides 2-4 ship without `src` so they don't
    // compete with slide 1 (the LCP element) for initial bandwidth — see
    // the comment in _includes/hero-carousel.html for the full rationale.
    function hydrate(slide) {
      const img = slide && slide.querySelector('img[data-src]');
      if (!img) return;
      img.src = img.dataset.src;
      img.removeAttribute('data-src');
    }

    function show(next) {
      index = ((next % slides.length) + slides.length) % slides.length;
      // Make sure the slide we're about to show — and the one after it,
      // so it's already decoded by the next tick — both have real sources.
      hydrate(slides[index]);
      hydrate(slides[(index + 1) % slides.length]);
      slides.forEach((slide, n) => {
        const active = n === index;
        slide.classList.toggle('is-active', active);
        slide.setAttribute('aria-hidden', active ? 'false' : 'true');
      });
      dots.forEach((dot, n) => {
        dot.setAttribute('aria-current', n === index ? 'true' : 'false');
      });
    }

    // Once the page has finished loading the LCP-critical assets, warm
    // up slide 2 in the background so it's ready before the first
    // auto-advance fires (~5s later). Falls back gracefully on browsers
    // without requestIdleCallback.
    const warmNext = () => hydrate(slides[1]);
    if (window.requestIdleCallback) {
      window.requestIdleCallback(warmNext, { timeout: 2000 });
    } else {
      window.setTimeout(warmNext, 1500);
    }

    function start() {
      if (reduceMotion) return;
      stop();
      timer = window.setInterval(() => show(index + 1), intervalMs);
    }

    function stop() {
      if (timer !== null) {
        window.clearInterval(timer);
        timer = null;
      }
    }

    dots.forEach((dot, n) => {
      dot.addEventListener('click', () => {
        show(n);
        start();
      });
    });

    root.addEventListener('mouseenter', stop);
    root.addEventListener('mouseleave', start);
    root.addEventListener('focusin', stop);
    root.addEventListener('focusout', start);
    root.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        show(index - 1);
        start();
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        show(index + 1);
        start();
      }
    });

    document.addEventListener('visibilitychange', () => {
      if (document.hidden) stop();
      else start();
    });

    start();
  }
})();

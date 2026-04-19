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

    function show(next) {
      index = ((next % slides.length) + slides.length) % slides.length;
      slides.forEach((slide, n) => {
        const active = n === index;
        slide.classList.toggle('is-active', active);
        slide.setAttribute('aria-hidden', active ? 'false' : 'true');
      });
      dots.forEach((dot, n) => {
        dot.setAttribute('aria-current', n === index ? 'true' : 'false');
      });
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

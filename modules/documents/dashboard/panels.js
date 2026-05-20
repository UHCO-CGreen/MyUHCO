document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('[data-dashboard-carousel="true"]').forEach(function (carouselEl) {
    var track = carouselEl.querySelector('[data-dashboard-carousel-track]');
    var prevBtn = carouselEl.querySelector('[data-dashboard-carousel-prev]');
    var nextBtn = carouselEl.querySelector('[data-dashboard-carousel-next]');

    if (!track || !prevBtn || !nextBtn) {
      return;
    }

    function getGapPx() {
      var styles = window.getComputedStyle(track);
      var gapPx = parseFloat(styles.columnGap || styles.gap || '0');
      return isNaN(gapPx) ? 0 : gapPx;
    }

    function getTargetColumns() {
      return Math.max(2, Math.min(10, Math.round(window.innerWidth / 240)));
    }

    function updateTileWidth() {
      var cols = getTargetColumns();
      var gapPx = getGapPx();
      var baselineTrackWidth = Math.max(track.clientWidth, carouselEl.clientWidth - 120, 240);
      var width = Math.floor((baselineTrackWidth - (gapPx * (cols - 1))) / cols);
      width = Math.max(120, Math.min(220, width));
      track.style.setProperty('--quick-docs-item-width', width + 'px');
    }

    function getScrollAmount() {
      var firstItem = track.querySelector('.quick-docs-item');
      var step = firstItem ? (firstItem.getBoundingClientRect().width + getGapPx()) : 220;
      return Math.max(220, Math.floor(step * 3));
    }

    function updateButtons() {
      updateTileWidth();
      var maxScrollLeft = Math.max(0, track.scrollWidth - track.clientWidth);
      var hasOverflow = maxScrollLeft > 2;

      prevBtn.classList.toggle('quick-docs-slider-btn--hidden', !hasOverflow);
      nextBtn.classList.toggle('quick-docs-slider-btn--hidden', !hasOverflow);

      if (!hasOverflow) {
        track.classList.add('quick-docs-track--centered');
        if (track.scrollLeft !== 0) {
          track.scrollLeft = 0;
        }
      } else {
        track.classList.remove('quick-docs-track--centered');
      }

      prevBtn.disabled = !hasOverflow || track.scrollLeft <= 2;
      nextBtn.disabled = !hasOverflow || track.scrollLeft >= (maxScrollLeft - 2);
    }

    prevBtn.addEventListener('click', function () {
      track.scrollBy({ left: -getScrollAmount(), behavior: 'smooth' });
    });

    nextBtn.addEventListener('click', function () {
      track.scrollBy({ left: getScrollAmount(), behavior: 'smooth' });
    });

    track.addEventListener('scroll', updateButtons);
    window.addEventListener('resize', updateButtons);
    window.addEventListener('load', updateButtons);
    updateButtons();
  });
});
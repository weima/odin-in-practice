(() => {
  const key = 'odin-book-font-size';
  const min = 16;
  const max = 24;
  const step = 2;
  const content = document.querySelector('.md-content__inner');
  if (!content) return;

  let size = 16;
  try {
    const saved = Number(localStorage.getItem(key));
    if (saved >= min && saved <= max && saved % step === 0) size = saved;
  } catch {}

  const controls = document.createElement('div');
  controls.className = 'font-size-controls';
  controls.setAttribute('role', 'group');
  controls.setAttribute('aria-label', 'Text size');
  const decrease = document.createElement('button');
  decrease.type = 'button';
  decrease.textContent = 'A−';
  decrease.setAttribute('aria-label', 'Decrease text size');
  const increase = document.createElement('button');
  increase.type = 'button';
  increase.textContent = 'A+';
  increase.setAttribute('aria-label', 'Increase text size');

  const apply = () => {
    content.style.setProperty('--book-font-size', `${size}px`);
    decrease.disabled = size === min;
    increase.disabled = size === max;
    try { localStorage.setItem(key, String(size)); } catch {}
  };
  decrease.addEventListener('click', () => { size = Math.max(min, size - step); apply(); });
  increase.addEventListener('click', () => { size = Math.min(max, size + step); apply(); });
  controls.append(decrease, increase);
  content.prepend(controls);
  apply();
})();

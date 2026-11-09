// Delegation also covers sidebar controls replaced by LiveView patches.
const selector = '.sidebar-rail .sidebar-link, .sidebar-rail .sidebar-menu-trigger, .sidebar-rail .avatar-trigger';
const tooltip = document.createElement('div');
tooltip.id = 'sidebar-tooltip';
tooltip.className = 'sidebar-tooltip';
tooltip.setAttribute('role', 'tooltip');
tooltip.hidden = true;
document.body.append(tooltip);

let active = null;
let timer;
let hideTimer;
const labelObserver = new MutationObserver(() => {
  if (active) {
    tooltip.textContent = active.getAttribute('aria-label');
    position();
  }
});

function position() {
  const rect = active.getBoundingClientRect();
  const gap = 12;
  const center = rect.top + rect.height / 2;
  const top = Math.max(gap, Math.min(center - tooltip.offsetHeight / 2, window.innerHeight - tooltip.offsetHeight - gap));
  tooltip.style.left = `${Math.max(gap, Math.min(rect.right + gap, window.innerWidth - tooltip.offsetWidth - gap))}px`;
  tooltip.style.top = `${top}px`;
  tooltip.style.setProperty('--tooltip-arrow-top', `${Math.max(10, Math.min(center - top, tooltip.offsetHeight - 10))}px`);
}

function hide() {
  clearTimeout(timer);
  clearTimeout(hideTimer);
  labelObserver.disconnect();
  if (active) {
    const ids = (active.getAttribute('aria-describedby') || '').split(/\s+/).filter(id => id && id !== tooltip.id);
    if (ids.length) active.setAttribute('aria-describedby', ids.join(' '));
    else active.removeAttribute('aria-describedby');
  }
  active = null;
  tooltip.hidden = true;
}

function show(target, delay) {
  clearTimeout(hideTimer);
  if (target === active) return;
  hide();
  if (target.closest('details[open]') || !target.getAttribute('aria-label')) return;
  active = target;
  timer = setTimeout(() => {
    if (!target.isConnected || !target.getClientRects().length) return hide();
    tooltip.textContent = target.getAttribute('aria-label');
    tooltip.hidden = false;
    position();
    const ids = [target.getAttribute('aria-describedby'), tooltip.id].filter(Boolean);
    target.setAttribute('aria-describedby', ids.join(' '));
    labelObserver.observe(target, {attributes: true, attributeFilter: ['aria-label']});
  }, delay);
}

document.addEventListener('pointerover', event => {
  if (event.pointerType === 'touch') return;
  const target = event.target.closest(selector);
  if (target) show(target, 300);
});
document.addEventListener('pointerout', event => {
  if (!active || active.contains(event.relatedTarget) || tooltip.contains(event.relatedTarget)) return;
  if (active.contains(event.target) || tooltip.contains(event.target)) {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(hide, 120);
  }
});
tooltip.addEventListener('pointerenter', () => clearTimeout(hideTimer));
document.addEventListener('focusin', event => {
  if (!event.target.matches(':focus-visible')) return;
  const target = event.target.closest(selector);
  if (target) show(target, 0);
});
document.addEventListener('focusout', event => {
  if (active?.contains(event.target)) hide();
});
document.addEventListener('click', hide);
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') hide();
});
window.addEventListener('scroll', hide, true);
window.addEventListener('resize', hide);
document.addEventListener('phx:page-loading-start', hide);

// Native <details> owns the toggle; delegation survives LiveView navigation.
(() => {
  const menus = () => document.querySelectorAll('.mobile-nav-menu[open]');
  function close(menu, restoreFocus = false) {
    menu.open = false;
    if (restoreFocus) menu.querySelector('.mobile-nav-trigger')?.focus();
  }

  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    menus().forEach(menu => {
      // Let an expanded nested section close first.
      const section = event.target.closest('.mobile-nav-panel details[open]');
      if (section) {
        section.open = false;
        section.querySelector('summary')?.focus();
      } else {
        close(menu, true);
      }
      event.preventDefault();
    });
  });
  document.addEventListener('pointerdown', event => {
    menus().forEach(menu => {
      if (!menu.contains(event.target)) close(menu);
    });
  });
  document.addEventListener('click', event => {
    const action = event.target.closest('.mobile-nav-link, .mobile-nav-action');
    const menu = action?.closest('.mobile-nav-menu');
    if (menu) close(menu);
  });
  document.addEventListener('focusin', event => {
    menus().forEach(menu => {
      if (!menu.contains(event.target)) close(menu);
    });
  });
  window.addEventListener('phx:page-loading-start', () => menus().forEach(menu => close(menu)));
  window.matchMedia('(max-width: 640px)').addEventListener('change', event => {
    if (!event.matches) menus().forEach(menu => close(menu));
  });
})();

// Watch the rendered count, so additions, removals, and quantity edits share
// one lightweight animation without changing layout or scrolling the page.
(() => {
  let observer;
  const animations = new WeakMap();
  function watchCart() {
    observer?.disconnect();
    const root = document.querySelector('#pos-live[data-cart-count]');
    if (!root) return;
    let previousCount = Number(root.dataset.cartCount) || 0;
    observer = new MutationObserver(() => {
      const count = Number(root.dataset.cartCount) || 0;
      if (count === previousCount) return;
      const scale = count > previousCount ? 1.18 : 0.88;
      previousCount = count;
      if (!window.matchMedia('(max-width: 640px)').matches || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      root.querySelectorAll('.mobile-topbar-cart, .sidebar-link:has(.sidebar-cart-count), .mobile-nav-link:has(.sidebar-cart-count), .order-panel.is-mobile-open .order-header .eyebrow').forEach(target => {
        if (!target.getClientRects().length) return;
        animations.get(target)?.cancel();
        const animation = target.animate?.([
          {transform: 'scale(1)'},
          {transform: `scale(${scale})`, offset: 0.3},
          {transform: `scale(${scale > 1 ? 0.96 : 1.06})`, offset: 0.65},
          {transform: 'scale(1)'}
        ], {duration: 420, easing: 'ease-out'});
        if (animation) animations.set(target, animation);
      });
    });
    observer.observe(root, {attributes: true, attributeFilter: ['data-cart-count']});
  }
  watchCart();
  window.addEventListener('phx:page-loading-stop', watchCart);
})();

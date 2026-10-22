(() => {
  const controls = document.querySelector('.preview-controls');
  const image = document.querySelector('#preview-image');
  const stage = document.querySelector('.preview-stage');
  const caption = document.querySelector('#preview-caption');
  let theme = 'light';
  let view = 'controls';
  let request = 0;
  if (controls && image && stage && caption) {
    const update = () => {
      const ticket = ++request;
      const next = new Image();
      const themeName = theme === 'light' ? 'claro' : 'escuro';
      const viewName = view === 'controls' ? 'Controles' : 'Direção do ar';
      const src = `assets/screenshots/${view}-${theme}.png`;
      const selectedTheme = theme;
      const selectedView = view;
      next.onload = () => {
        if (ticket !== request) return;
        image.src = src;
        image.alt = `${viewName} do UbiAir no tema ${themeName}, em demonstração`;
        stage.dataset.appearance = selectedTheme;
        caption.textContent = `${viewName} no tema ${themeName}. Captura da interface SwiftUI com aparelhos fictícios.`;
        controls.querySelectorAll('[data-theme]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.theme === selectedTheme)));
        controls.querySelectorAll('[data-view]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.view === selectedView)));
        if (!matchMedia('(prefers-reduced-motion: reduce)').matches && image.animate) image.animate([{opacity:.4,transform:'translateY(6px)'},{opacity:1,transform:'none'}],{duration:240,easing:'ease-out'});
      };
      next.onerror = () => { if (ticket === request) caption.textContent = 'Não foi possível abrir esta captura. A imagem anterior continua disponível.'; };
      next.src = src;
    };
    controls.hidden = false;
    controls.addEventListener('click', event => {
      const button = event.target.closest('button');
      if (!button) return;
      if (button.dataset.theme) theme = button.dataset.theme;
      if (button.dataset.view) view = button.dataset.view;
      update();
    });
  }
  // An anchor must open its disclosure before the browser scrolls to it.
  document.querySelectorAll('a[href="#instalacao"]').forEach(link => link.addEventListener('click', () => { document.querySelector('#instalacao').open = true; }));
  if (location.hash === '#instalacao') document.querySelector('#instalacao').open = true;

  // Animate only content entering the viewport; the underlying page stays visible
  // if scripting, observers or the animation API are unavailable.
  const calm = matchMedia('(prefers-reduced-motion: reduce)');
  if (!calm.matches && 'IntersectionObserver' in window && Element.prototype.animate) {
    const groups = [
      ['.hero-copy > *', 'rise'],
      ['.hero-panel-light, .hero-panel-dark', 'settle'],
      ['.feature-picture > *, .feature-content h2, .feature-points > *, .feature-note', 'rise'],
      ['.showcase-copy > *, .preview-photo', 'settle'],
      ['.onboard-intro > *, .onboard-steps > li, .installation, .demo-note', 'rise'],
      ['.faq-content > *, .faq-picture > img', 'settle'],
      ['.closing-copy > *, .closing-object', 'rise'],
      ['.footer-wordmark, .footer-content, .footer-notes', 'settle']
    ];
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        observer.unobserve(entry.target);
        if (calm.matches) return;
        const settle = entry.target.dataset.entrance === 'settle';
        entry.target.animate([
          {opacity: .25, transform: settle ? 'translateY(18px) scale(.98)' : 'translateY(24px)'},
          {opacity: 1, transform: 'none'}
        ], {duration: settle ? 850 : 650, delay: Number(entry.target.dataset.delay), easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards'});
      });
    }, {threshold:.08});
    groups.forEach(([selector, entrance]) => {
      document.querySelectorAll(selector).forEach((element, index) => {
        element.dataset.entrance = entrance;
        element.dataset.delay = String(index % 3 * 70);
        observer.observe(element);
      });
    });
    calm.addEventListener('change', () => {
      if (calm.matches) document.getAnimations().forEach(animation => animation.cancel());
    });
  }
})();

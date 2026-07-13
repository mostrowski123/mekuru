(() => {
  if (!window.location.hash.startsWith('#/')) return;

  const legacyPath = window.location.hash.slice(2).split('?')[0];
  const normalized = legacyPath.replace(/\.md$/, '').replace(/^\/+|\/+$/g, '');
  const destination =
    normalized === '' || normalized === 'home'
      ? '/documentation/'
      : `/documentation/${normalized}/`;

  window.location.replace(destination);
})();

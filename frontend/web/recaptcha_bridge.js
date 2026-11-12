// Google renders its real widget; this bridge never decides authentication.
(() => {
  const entries = new WeakMap();
  window.aidTrackCaptcha = {
    mount(element, siteKey, callback) {
      this.unmount(element);
      const entry = {active: true, timer: null, widgetId: null};
      entries.set(element, entry);
      const started = Date.now();
      const notify = (token, state) => {
        if (entry.active) callback(token, state);
      };
      const render = () => {
        if (!entry.active) return;
        if (element.isConnected && window.grecaptcha?.render) {
          try {
            entry.widgetId = grecaptcha.render(element, {
              sitekey: siteKey,
              size: 'normal',
              theme: 'light',
              callback: token => notify(token, 'verified'),
              'expired-callback': () => notify('', 'expired'),
              'error-callback': () => notify('', 'error')
            });
            notify('', 'ready');
          } catch (_) { notify('', 'error'); }
          return;
        }
        if (Date.now() - started > 15000) {
          notify('', 'error');
          return;
        }
        entry.timer = setTimeout(render, 100);
      };
      entry.timer = setTimeout(render, 0);
    },
    unmount(element) {
      const entry = entries.get(element);
      if (!entry) return;
      entry.active = false;
      clearTimeout(entry.timer);
      if (entry.widgetId !== null && window.grecaptcha?.reset) {
        try { grecaptcha.reset(entry.widgetId); } catch (_) {}
      }
      element.replaceChildren();
      entries.delete(element);
    }
  };
})();

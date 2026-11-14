/// Browser controls and live cache updates; the Swift forms work without scripting.
enum BrowserControls {
  static let source = #"""
  (() => {
    if (!window.fetch || !window.FormData || !window.URLSearchParams) return;

    const message = (card, text, error = false) => {
      const feedback = card.querySelector('[data-feedback]');
      if (!feedback) return;
      const node = document.createElement('p');
      node.setAttribute('role', error ? 'alert' : 'status');
      if (error) node.className = 'error';
      node.textContent = text;
      feedback.replaceChildren(node);
    };
    const status = text => {
      const node = document.getElementById('live-updates');
      if (node) node.textContent = text;
    };
    const parseCard = async (response, id) => {
      if (!(response.headers.get('Content-Type') || '').startsWith('text/html')) throw new Error('Unexpected response');
      const template = document.createElement('template');
      template.innerHTML = await response.text();
      const card = template.content.firstElementChild;
      if (template.content.childElementCount !== 1 || !card.matches('article[data-device-card]') ||
          card.id !== id || card.querySelector('script,iframe,object,embed')) throw new Error('Unexpected fragment');
      return card;
    };
    const install = (card, replacement, rememberedFocus = null, preserveFeedback = false) => {
      const x = window.scrollX, y = window.scrollY;
      if (card) {
        const oldLevel = card.querySelector('input[name="levelPercent"]');
        const newLevel = replacement.querySelector('input[name="levelPercent"]');
        if (oldLevel && newLevel) newLevel.value = oldLevel.value;
        if (preserveFeedback) {
          const feedback = card.querySelector('[data-feedback]');
          const target = replacement.querySelector('[data-feedback]');
          if (feedback && target) target.replaceChildren(...Array.from(feedback.childNodes).map(node => node.cloneNode(true)));
        }
        const focus = card.contains(document.activeElement) ? document.activeElement :
          document.activeElement === document.body ? rememberedFocus : null;
        const formIndex = focus ? Array.from(card.querySelectorAll('form')).indexOf(focus.closest('form')) : -1;
        card.replaceWith(replacement);
        if (formIndex >= 0) {
          const form = replacement.querySelectorAll('form')[formIndex];
          const next = focus.name ? form?.elements.namedItem(focus.name) : form?.querySelector('button');
          next?.focus({ preventScroll: true });
        }
      } else {
        document.querySelector('[data-empty-devices]')?.remove();
        document.querySelector('main.devices')?.append(replacement);
      }
      window.scrollTo(x, y);
    };

    // Queue and coalesce safe cache reads. Hardware POSTs are never retried.
    const queue = new Set();
    const validAddress = address => typeof address === 'string' && /^[0-9A-F]{2}(\.[0-9A-F]{2}){2}$/i.test(address);
    let reading = false, listNeeded = false, retryTimer = 0, retryDelay = 500;
    let active = true, generation = 0, authenticationRequired = false, events = null, connected = false;
    let cacheController = null, cacheTimeout = 0;
    const liveSupported = Boolean(window.EventSource && window.AbortController);
    const readCache = url => {
      clearTimeout(cacheTimeout);
      cacheController = new AbortController();
      const controller = cacheController;
      cacheTimeout = setTimeout(() => controller.abort(), 10000);
      return fetch(url, { credentials: 'same-origin', redirect: 'error', cache: 'no-store', signal: controller.signal });
    };
    const authenticate = () => {
      authenticationRequired = true;
      events?.close();
      events = null;
      queue.clear();
      listNeeded = false;
      clearTimeout(retryTimer);
      retryTimer = 0;
      cacheController?.abort();
      status('Authentication is required. Reload this page to sign in.');
    };
    const retry = () => {
      if (retryTimer || !active || authenticationRequired) return;
      retryTimer = setTimeout(() => { retryTimer = 0; drain(); }, retryDelay);
      retryDelay = Math.min(retryDelay * 2, 10000);
    };
    const drain = async () => {
      if (!liveSupported || reading || retryTimer || !active || authenticationRequired) return;
      reading = true;
      const epoch = generation;
      try {
        if (listNeeded) {
          listNeeded = false;
          try {
            const response = await readCache('/api/v1/devices');
            if (!active || epoch !== generation) return;
            if (response.status === 401) { authenticate(); return; }
            if (!response.ok) throw new Error('Cache unavailable');
            const list = await response.json();
            if (list.version !== 1 || !Array.isArray(list.devices)) throw new Error('Unexpected list');
            if (!active || epoch !== generation) return;
            list.devices.forEach(device => { if (validAddress(device.address)) queue.add(device.address.toUpperCase()); });
          } catch (error) {
            listNeeded = true;
            throw error;
          }
        }
        while (active && epoch === generation && queue.size) {
          const address = Array.from(queue).find(value => document.getElementById('device-' + value)?.dataset.pending !== 'true');
          if (!address) break;
          queue.delete(address);
          const id = 'device-' + address;
          const original = document.getElementById(id);
          try {
            const response = await readCache('/devices/' + encodeURIComponent(address));
            if (!active || epoch !== generation) return;
            if (response.status === 401) { authenticate(); return; }
            const current = document.getElementById(id);
            if (!active || epoch !== generation) return;
            if (current !== original || current?.dataset.pending === 'true') { queue.add(address); continue; }
            if (response.status === 404) {
              if (current) message(current, 'This device is unavailable. Refresh the page.', true);
              continue;
            }
            if (!response.ok) throw new Error('Cache unavailable');
            const replacement = await parseCard(response, id);
            // A local command can finish while response.text() is awaiting the body.
            if (!active || epoch !== generation) return;
            if (document.getElementById(id) !== original || original?.dataset.pending === 'true') { queue.add(address); continue; }
            install(original, replacement, null, true);
          } catch (error) {
            queue.add(address);
            throw error;
          }
        }
        retryDelay = 500;
        if (connected) status('Live updates connected.');
      } catch {
        if (active && epoch === generation && !authenticationRequired) {
          status('Live updates temporarily unavailable. Retrying…');
          retry();
        }
      } finally {
        clearTimeout(cacheTimeout);
        cacheController = null;
        reading = false;
        // A cached-page restore may have queued a resync while this old read was active.
        if (listNeeded && !retryTimer && active && !authenticationRequired) Promise.resolve().then(drain);
      }
    };
    const synchronize = () => {
      if (!liveSupported || authenticationRequired) return;
      listNeeded = true;
      if (reading) cacheController?.abort();
      clearTimeout(retryTimer);
      retryTimer = 0;
      retryDelay = 500;
      drain();
    };
    const connect = () => {
      if (!liveSupported) { status('Live updates are unavailable in this browser. Use Refresh page.'); return; }
      if (events || !active || authenticationRequired) return;
      status('Connecting live updates…');
      const connection = new EventSource('/api/v1/events');
      events = connection;
      connection.onopen = () => {
        if (!active || events !== connection) return;
        connected = true; status('Live updates connected.'); synchronize();
      };
      connection.onerror = () => {
        if (!active || events !== connection) return;
        connected = false; status('Live updates paused. Displayed values may be stale.');
      };
      connection.onmessage = event => {
        if (!active || events !== connection) return;
        try {
          const update = JSON.parse(event.data);
          if (update?.version !== 1 || !validAddress(update.address)) return;
          if (!['commandCompleted', 'identified', 'setButtonPressed'].includes(update.kind)) return;
          queue.add(update.address.toUpperCase());
          drain();
        } catch { /* Unknown or malformed events don't execute commands. */ }
      };
    };

    document.addEventListener('submit', async event => {
      const form = event.target;
      if (!(form instanceof HTMLFormElement)) return;
      const card = form.closest('article[data-device-card]');
      if (!card) return;
      event.preventDefault();
      if (card.dataset.pending === 'true') return;
      if (authenticationRequired) { message(card, 'Authentication is required. Reload this page to sign in.', true); return; }

      const body = new URLSearchParams(new FormData(form));
      const buttons = Array.from(card.querySelectorAll('button')).map(button => [button, button.disabled]);
      const focus = card.contains(document.activeElement) ? document.activeElement : null;
      card.dataset.pending = 'true';
      card.setAttribute('aria-busy', 'true');
      buttons.forEach(([button]) => { button.disabled = true; });
      message(card, 'Working…');
      try {
        // The hidden input named action shadows form.action in the browser DOM.
        const response = await fetch(form.getAttribute('action'), {
          method: 'POST', credentials: 'same-origin', redirect: 'error',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Insteon-Fragment': 'device' }, body
        });
        if (response.status === 401) { authenticate(); message(card, 'Authentication is required. Reload this page to sign in.', true); return; }
        install(card, await parseCard(response, card.id), focus);
      } catch {
        message(card, 'Could not update this card. The command may have reached the device. Read status before repeating a control.', true);
      } finally {
        if (card.isConnected) {
          delete card.dataset.pending;
          card.removeAttribute('aria-busy');
          buttons.forEach(([button, disabled]) => { button.disabled = disabled; });
        }
        drain();
      }
    });
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') { connect(); synchronize(); } });
    window.addEventListener('pagehide', () => {
      active = false;
      generation++;
      connected = false;
      events?.close();
      events = null;
      clearTimeout(retryTimer);
      retryTimer = 0;
      cacheController?.abort();
      clearTimeout(cacheTimeout);
      listNeeded = true;
    });
    window.addEventListener('pageshow', event => { active = true; connect(); if (event.persisted) synchronize(); });
    connect();
  })();
  """#
}

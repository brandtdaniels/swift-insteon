/// A small browser enhancement. The Swift form handler remains usable without scripting.
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

    document.addEventListener('submit', async event => {
      const form = event.target;
      if (!(form instanceof HTMLFormElement)) return;
      const card = form.closest('article[data-device-card]');
      if (!card) return;
      event.preventDefault();
      if (card.dataset.pending === 'true') return;

      // Serialize before disabling anything. Never retry a hardware command automatically.
      const body = new URLSearchParams(new FormData(form));
      const buttons = Array.from(card.querySelectorAll('button')).map(button => [button, button.disabled]);
      const focus = document.activeElement;
      const focusedHere = card.contains(focus);
      const formIndex = Array.from(card.querySelectorAll('form')).indexOf(form);
      card.dataset.pending = 'true';
      card.setAttribute('aria-busy', 'true');
      buttons.forEach(([button]) => { button.disabled = true; });
      message(card, 'Working…');

      try {
        // The hidden input named action shadows form.action in the browser DOM.
        const response = await fetch(form.getAttribute('action'), {
          method: 'POST',
          credentials: 'same-origin',
          redirect: 'error',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-Insteon-Fragment': 'device'
          },
          body
        });
        if (response.status === 401) {
          message(card, 'Authentication is required. Reload this page to sign in.', true);
          return;
        }
        if (!(response.headers.get('Content-Type') || '').startsWith('text/html')) {
          throw new Error('Unexpected response');
        }
        const template = document.createElement('template');
        template.innerHTML = await response.text();
        const replacement = template.content.firstElementChild;
        if (template.content.childElementCount !== 1 ||
            !replacement.matches('article[data-device-card]') || replacement.id !== card.id ||
            replacement.querySelector('script,iframe,object,embed')) {
          throw new Error('Unexpected fragment');
        }

        // Other cards retain their DOM, edits, and focus. Keep this card's level input too.
        const oldLevel = card.querySelector('input[name="levelPercent"]');
        const newLevel = replacement.querySelector('input[name="levelPercent"]');
        if (oldLevel && newLevel) newLevel.value = oldLevel.value;
        const x = window.scrollX;
        const y = window.scrollY;
        const restoreFocus = focusedHere &&
          (document.activeElement === document.body || card.contains(document.activeElement));
        card.replaceWith(replacement);
        if (restoreFocus) {
          const nextForm = replacement.querySelectorAll('form')[formIndex];
          const nextFocus = focus.name ? nextForm?.elements.namedItem(focus.name) : nextForm?.querySelector('button');
          nextFocus?.focus({ preventScroll: true });
        }
        window.scrollTo(x, y);
      } catch {
        message(card, 'Could not update this card. The command may have reached the device. Read status before repeating a control.', true);
      } finally {
        if (card.isConnected) {
          delete card.dataset.pending;
          card.removeAttribute('aria-busy');
          buttons.forEach(([button, disabled]) => { button.disabled = disabled; });
        }
      }
    });
  })();
  """#
}

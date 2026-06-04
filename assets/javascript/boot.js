// Elm boot + scripted MOCK (offline, no network).
//
// The Elm app talks to its sendToOpenAi / openAiEvent ports. This script answers
// each request with a scripted, streamed reply so the interaction can be shown
// without a backend. To prototype your own idea, replace this scenario (and the
// Elm view) — the port contract is the only thing that needs to stay stable.
//
// Event shapes the Elm app understands:
//   { type: 'delta', text }            — append streamed text to the live bubble
//   { type: 'questions', questions }   — render a row of clickable option chips
//   { type: 'done' }                   — end of stream; commit the bubble
//   { type: 'error', message }         — show an error bubble

(() => {
  'use strict';

  // A scripted reply per user turn. The last entry repeats for any further turns.
  const REPLIES = [
    'Thanks for trying the starter — this is a fully offline mock, no network calls. ' +
      'Your message went to the embedded Elm app over a port, and this script answered ' +
      'with a scripted, streamed reply. What would you like to look at?',
    'Here it is, streaming word by word: the Elm app appends each delta to the live ' +
      'bubble, then commits it once the stream ends. Anything else?',
    'That is the whole loop — message → port → scripted events → rendered chat. ' +
      'Replace boot.js with your mock and elm/src with your UI to prototype a redesign fast.',
  ];

  // Optional chips offered after a reply, by turn. `null` = no chips that turn.
  const QUESTIONS = [
    { prompt: '', options: ['Show me streaming', 'How do sessions work?', 'Just echo my message'] },
    { prompt: '', options: ['Tell me about deploys', 'How is accessibility checked?', "I'm good, thanks"] },
    null,
  ];

  let step = 0; // count of user turns handled

  const flagsFor = (node) => ({
    pageTitle: node.getAttribute('data-page-title') || 'Ask the mock assistant',
    inputPlaceholder:
      node.getAttribute('data-input-placeholder') || 'Type a message and press Enter…',
  });

  // A tiny scheduler: `at` queues work on a growing timeline; `stream` emits a
  // string word-by-word as `delta` events, then calls `after`.
  const runner = (emit) => {
    let t = 0;
    const at = (delay, fn) => { t += delay; window.setTimeout(fn, t); };
    const stream = (textValue, after) => {
      textValue.split(' ').forEach((word, i) => {
        at(30, () => emit({ type: 'delta', text: i === 0 ? word : ' ' + word }));
      });
      at(120, after);
    };
    return { at, stream };
  };

  const handle = (emit) => {
    const { at, stream } = runner(emit);
    const i = Math.min(step, REPLIES.length - 1);
    const reply = REPLIES[i];
    const question = QUESTIONS[Math.min(step, QUESTIONS.length - 1)];
    step += 1;

    stream(reply, () => {
      if (question) {
        at(0, () => emit({ type: 'questions', questions: [question] }));
      }
      at(0, () => emit({ type: 'done' }));
    });
  };

  const startElm = (node) => {
    if (!window.Elm || !window.Elm.Main) {
      node.textContent = 'Elm bundle not loaded.';
      return;
    }
    const flags = flagsFor(node);
    const app = window.Elm.Main.init({ node, flags });
    const emit = (event) => app.ports.openAiEvent.send(event);
    app.ports.sendToOpenAi.subscribe(() => handle(emit));
  };

  const boot = () => {
    document.querySelectorAll('[data-mock-app]').forEach(startElm);
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();

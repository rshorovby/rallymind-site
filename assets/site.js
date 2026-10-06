/* =========================================================
   Лендинг SwingSync — минимум скриптов.
   Без сборки и зависимостей: то, что можно сделать на HTML/CSS,
   сделано на HTML/CSS. Здесь только то, что ими не выражается.
   ========================================================= */

/* ---------------------------------------------------------
   ЦИФРЫ НА САЙТЕ
   Заполни то, что готов показать. Незаполненное просто
   не появится: пустых блоков и выдуманных значений не будет.
   Если не заполнено ничего — секция целиком остаётся скрытой.

   Пример:
     players: 128, analyses: 640, score: 3.8
   --------------------------------------------------------- */

const STATS = {
  players: null,
  analyses: null,
  score: null,
};

/* ---------------------------------------------------------
   Тема: следуем системной, но запоминаем ручной выбор,
   если он когда-нибудь появится (localStorage['rally-theme']).
   --------------------------------------------------------- */

(function theme() {
  const media = window.matchMedia('(prefers-color-scheme: dark)');

  function stored() {
    try {
      return localStorage.getItem('rally-theme');
    } catch (error) {
      return null;
    }
  }

  function apply(isDark) {
    const root = document.documentElement;
    if (isDark) {
      root.dataset.theme = 'dark';
    } else {
      delete root.dataset.theme;
    }
  }

  const chosen = stored();
  apply(chosen ? chosen === 'dark' : media.matches);

  media.addEventListener('change', function (event) {
    if (!stored()) {
      apply(event.matches);
    }
  });
})();

/* ---------------------------------------------------------
   Цифры: подстановка и локализация разделителя разрядов.
   --------------------------------------------------------- */

(function stats() {
  const section = document.getElementById('stats');
  if (!section) {
    return;
  }

  const locale = document.documentElement.lang === 'ru' ? 'ru-RU' : 'en-US';
  const filled = Object.keys(STATS).filter(function (key) {
    return STATS[key] !== null && STATS[key] !== undefined;
  });

  if (filled.length === 0) {
    return;
  }

  const cards = section.querySelectorAll('.stat');
  let visible = 0;

  cards.forEach(function (card) {
    const value = card.querySelector('[data-stat]');
    const key = value ? value.dataset.stat : null;
    const number = key ? STATS[key] : null;

    if (number === null || number === undefined) {
      card.remove();
      return;
    }

    value.textContent = typeof number === 'number'
      ? number.toLocaleString(locale, { maximumFractionDigits: 1 })
      : number;
    visible += 1;
  });

  if (visible > 0) {
    section.hidden = false;
  }
})();

/* ---------------------------------------------------------
   Появление секций при скролле. Без IntersectionObserver
   контент показывается сразу — он не должен зависеть от JS.
   --------------------------------------------------------- */

(function reveal() {
  const blocks = document.querySelectorAll('.reveal');

  if (!('IntersectionObserver' in window)) {
    blocks.forEach(function (block) {
      block.classList.add('is-visible');
    });
    return;
  }

  const observer = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    },
    { rootMargin: '0px 0px -12% 0px', threshold: 0.08 }
  );

  blocks.forEach(function (block) {
    observer.observe(block);
  });
})();

/* ---------------------------------------------------------
   Год в футере.
   --------------------------------------------------------- */

(function year() {
  const node = document.querySelector('[data-year]');
  if (node) {
    node.textContent = String(new Date().getFullYear());
  }
})();

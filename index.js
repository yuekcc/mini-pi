/* mp · GitHub Pages — 原生交互 */
(function () {
  "use strict";

  /* 当前年份 */
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  /* 滚动揭示（带兜底，确保内容永不隐藏） */
  var revealEls = document.querySelectorAll(".reveal");
  function revealNow(el) { el.classList.add("is-in"); }
  function revealInView() {
    var vh = window.innerHeight || document.documentElement.clientHeight;
    revealEls.forEach(function (el) {
      if (el.classList.contains("is-in")) return;
      var r = el.getBoundingClientRect();
      if (r.top < vh * 0.94 && r.bottom > 0) revealNow(el);
    });
  }
  try {
    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              revealNow(entry.target);
              io.unobserve(entry.target);
            }
          });
        },
        { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
      );
      revealEls.forEach(function (el) { io.observe(el); });
    } else {
      revealEls.forEach(revealNow);
    }
  } catch (err) {
    revealEls.forEach(revealNow);
  }
  window.addEventListener("load", revealInView);
  window.addEventListener("scroll", revealInView, { passive: true });
  revealInView();

  /* 导航高亮（滚动監听） */
  var sections = Array.prototype.slice.call(document.querySelectorAll("main section[id]"));
  var navLinks = Array.prototype.slice.call(document.querySelectorAll(".nav__link[href^='#']"));
  function setActive(id) {
    navLinks.forEach(function (a) {
      a.classList.toggle("is-active", a.getAttribute("href") === "#" + id);
    });
  }
  if ("IntersectionObserver" in window && sections.length) {
    var spy = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) setActive(entry.target.id);
        });
      },
      { rootMargin: "-45% 0px -50% 0px" }
    );
    sections.forEach(function (s) { spy.observe(s); });
  }

  /* 复制按钮 */
  function copyText(text, btn) {
    var done = function () {
      var old = btn.textContent;
      btn.textContent = "已复制";
      btn.classList.add("is-ok");
      setTimeout(function () { btn.textContent = old; btn.classList.remove("is-ok"); }, 1400);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { fallback(text, done); });
    } else {
      fallback(text, done);
    }
  }
  function fallback(text, cb) {
    var ta = document.createElement("textarea");
    ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(ta); cb();
  }

  document.querySelectorAll("[data-copy]").forEach(function (el) {
    var btn = el.querySelector(".cmdline__copy, .codeblock__copy");
    if (!btn) return;
    btn.addEventListener("click", function (e) {
      e.preventDefault();
      copyText(el.getAttribute("data-copy"), btn);
    });
  });

  /* 移动端导航 */
  var toggle = document.getElementById("navToggle");
  var nav = document.querySelector(".nav");
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    nav.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () {
        nav.classList.remove("is-open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }
})();

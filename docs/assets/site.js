/* ------------------------------------------------------------------
   Squeeze website: edit these values before publishing.
   Every download / GitHub / donate / email link on every page
   is filled in from here, so you only change them once.
------------------------------------------------------------------- */
window.SQUEEZE = {
  githubRepo: "sary1511/squeeze",   // owner/repo on GitHub
  version: "1.0.1",
  // Contact form → your Google Form (answers land in Google Forms / Sheets, with email alerts).
  googleForm: {
    id: "1FAIpQLScmj8xxy6K9yfHe-Butb9-ITxBzd1NVE1-kusHGXxH_93hKgQ",                  // the long code between /d/e/ and /viewform
    fields: {
      name: "entry.749863436",
      email: "entry.1879949237",
      topic: "entry.1423824627",
      message: "entry.369175984",
    },
  },
  donateUrl: "",                                // add a link later (GitHub Sponsors, Buy Me a Coffee…) to show Support buttons
  email: "sarthak10raut@gmail.com",
  publisher: "Sarthak",
};

(function () {
  const c = window.SQUEEZE;
  const repo = `https://github.com/${c.githubRepo}`;
  const links = {
    // GitHub always serves the newest release at this address.
    // Until GitHub answers (or if it can't), Download opens the latest release page.
    download: `${repo}/releases/latest`,
    github: repo,
    releases: `${repo}/releases`,
    issues: `${repo}/issues/new/choose`,
    license: `${repo}/blob/main/LICENSE`,
    donate: c.donateUrl,
    email: `mailto:${c.email}`,
  };

  document.querySelectorAll("[data-link]").forEach((el) => {
    const href = links[el.dataset.link];
    if (href) el.setAttribute("href", href);
    else if (el.dataset.link === "donate") el.hidden = true;   // no donation link yet
  });
  document.querySelectorAll("[data-text]").forEach((el) => {
    const value = c[el.dataset.text];
    if (value) el.textContent = value;
  });
  // Point every Download button straight at the .dmg in the newest release,
  // whatever it's called (e.g. Squeeze_v1.0.1.dmg), and show its version.
  (async () => {
    const key = `squeeze-latest:${c.githubRepo}`;
    let info = null;
    try { info = JSON.parse(sessionStorage.getItem(key) || "null"); } catch {}
    if (!info) {
      try {
        const res = await fetch(`https://api.github.com/repos/${c.githubRepo}/releases/latest`, {
          headers: { Accept: "application/vnd.github+json" },
        });
        if (!res.ok) return;
        const release = await res.json();
        const dmg = (release.assets || []).find((a) => /\.dmg$/i.test(a.name));
        info = {
          url: dmg ? dmg.browser_download_url : release.html_url,
          version: (release.tag_name || "").replace(/^v/i, ""),
        };
        try { sessionStorage.setItem(key, JSON.stringify(info)); } catch {}
      } catch { return; }
    }
    document.querySelectorAll('[data-link="download"]').forEach((el) => el.setAttribute("href", info.url));
    if (info.version) document.querySelectorAll('[data-text="version"]').forEach((el) => (el.textContent = info.version));
  })();

  document.querySelectorAll("[data-year]").forEach((el) => (el.textContent = new Date().getFullYear()));

  // Header gets a glass background once the page scrolls.
  const header = document.querySelector(".site-header");
  if (header) {
    const onScroll = () => header.classList.toggle("scrolled", window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  // Background videos: honour reduced motion, and pause any that are off screen.
  const videos = document.querySelectorAll("video[autoplay]");
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
    videos.forEach((v) => { v.removeAttribute("autoplay"); v.pause(); });
  } else if ("IntersectionObserver" in window) {
    const vio = new IntersectionObserver((entries) => entries.forEach((e) => {
      const v = e.target;
      if (e.isIntersecting) { const p = v.play(); if (p) p.catch(() => {}); } else { v.pause(); }
    }));
    videos.forEach((v) => vio.observe(v));
  }

  // Mobile menu.
  const toggle = document.querySelector(".menu-toggle");
  if (toggle) {
    toggle.addEventListener("click", () => {
      const open = document.body.classList.toggle("menu-open");
      toggle.setAttribute("aria-expanded", String(open));
    });
    document.querySelectorAll(".nav-links a").forEach((a) =>
      a.addEventListener("click", () => {
        document.body.classList.remove("menu-open");
        toggle.setAttribute("aria-expanded", "false");
      })
    );
  }

  // Fade sections in as they scroll into view (skipped for reduced motion).
  if ("IntersectionObserver" in window && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
    const io = new IntersectionObserver(
      (entries) => entries.forEach((e) => e.isIntersecting && (e.target.classList.add("in"), io.unobserve(e.target))),
      { rootMargin: "0px 0px -10% 0px" }
    );
    document.querySelectorAll(".reveal").forEach((el) => io.observe(el));
  } else {
    document.querySelectorAll(".reveal").forEach((el) => el.classList.add("in"));
  }

  // Contact form → Google Forms, sent in the background so the page doesn't change.
  // Google doesn't let other sites read its reply (no-cors), so a request that
  // reaches Google counts as sent; only a network failure shows the error.
  const form = document.querySelector("#contact-form");
  if (form) {
    const gf = c.googleForm || {};
    const status = form.querySelector(".form-status");
    const configured = gf.id && !gf.id.startsWith("your-");
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const data = new FormData(form);
      if (data.get("_gotcha")) return;              // spam bot filled the hidden field
      const button = form.querySelector("button[type=submit]");
      status.className = "form-status";
      if (!configured) {
        status.classList.add("error");
        status.innerHTML = `The contact form isn't set up yet. Please email <a href="${links.email}">${c.email}</a>.`;
        return;
      }
      button.disabled = true;
      status.textContent = "Sending…";
      const body = new URLSearchParams();
      for (const [key, entry] of Object.entries(gf.fields || {})) {
        body.append(entry, (data.get(key) || "").toString());
      }
      try {
        await fetch(`https://docs.google.com/forms/d/e/${gf.id}/formResponse`, {
          method: "POST",
          mode: "no-cors",
          body,
        });
        form.reset();
        status.classList.add("ok");
        status.textContent = "Thanks! Your message is on its way. I usually reply within a few days.";
      } catch {
        status.classList.add("error");
        status.innerHTML = `Couldn't send that. Please email <a href="${links.email}">${c.email}</a> instead.`;
      } finally {
        button.disabled = false;
      }
    });
  }
})();

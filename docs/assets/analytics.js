/* ------------------------------------------------------------------
   Google Analytics 4 with Consent Mode.
   - Ads features are always off.
   - EU/EEA, UK and Switzerland: analytics cookies stay off until the
     visitor clicks "Accept" (Google then only gets cookieless pings).
   - Everywhere else: analytics is on unless the visitor clicks "Decline".
   The choice is remembered in this browser and can be changed from the
   "Cookie settings" link in the footer.
------------------------------------------------------------------- */
(function () {
  var GA_ID = "G-ZHCWCHFENZ";
  var KEY = "squeeze-consent";               // "granted" | "denied"
  var EU = ["AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR","DE","GR","HU","IE","IT","LV","LT","LU","MT","NL","PL","PT","RO","SK","SI","ES","SE","IS","LI","NO","GB","CH"];

  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  window.gtag = gtag;

  var denyAds = { ad_storage: "denied", ad_user_data: "denied", ad_personalization: "denied" };
  gtag("consent", "default", Object.assign({ analytics_storage: "denied", region: EU, wait_for_update: 500 }, denyAds));
  gtag("consent", "default", Object.assign({ analytics_storage: "granted" }, denyAds));

  var saved = null;
  try { saved = localStorage.getItem(KEY); } catch (e) {}
  if (saved) gtag("consent", "update", { analytics_storage: saved });

  gtag("js", new Date());
  gtag("config", GA_ID, { anonymize_ip: true });

  // gtag.js itself is loaded by the <script async> tag right after this file in each page.

  function choose(value) {
    try { localStorage.setItem(KEY, value); } catch (e) {}
    gtag("consent", "update", { analytics_storage: value });
    var b = document.querySelector(".consent");
    if (b) b.remove();
  }

  function showBanner() {
    if (document.querySelector(".consent")) return;
    var b = document.createElement("div");
    b.className = "consent";
    b.setAttribute("role", "dialog");
    b.setAttribute("aria-label", "Cookie choice");
    b.innerHTML =
      '<p>This site uses Google Analytics cookies to count visits. No ads, no selling data. ' +
      '<a href="/privacy.html#website">Privacy</a></p>' +
      '<div class="consent-actions">' +
      '<button type="button" class="btn btn-outline" data-consent="denied">Decline</button>' +
      '<button type="button" class="btn btn-primary" data-consent="granted">Accept</button>' +
      "</div>";
    b.addEventListener("click", function (e) {
      var v = e.target.getAttribute && e.target.getAttribute("data-consent");
      if (v) choose(v);
    });
    document.body.appendChild(b);
  }

  function ready() {
    if (!saved) showBanner();
    // "Cookie settings" links reopen the banner.
    document.addEventListener("click", function (e) {
      var a = e.target.closest && e.target.closest("[data-cookie-settings]");
      if (a) { e.preventDefault(); showBanner(); }
      // Count Download clicks as an event.
      var d = e.target.closest && e.target.closest('[data-link="download"]');
      if (d) gtag("event", "download_click", { link_url: d.href });
    });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ready);
  else ready();
})();

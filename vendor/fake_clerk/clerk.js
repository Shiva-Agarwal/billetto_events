/*
 * Fake clerk-js for tests and credential-less local development.
 *
 * Implements the subset of the clerk-js browser SDK API the app uses:
 *   Clerk.load(), Clerk.user, Clerk.session.getToken(), Clerk.mountSignIn(el, opts),
 *   Clerk.mountSignUp(el, opts), Clerk.mountUserButton(el), Clerk.signOut({ redirectUrl })
 *
 * Accounts live in localStorage; the session token is written to the `__session` cookie as
 * "fake-clerk.<user id>", which ClerkAuth::FakeAdapter accepts on the server. Labels mirror
 * Clerk's real components ("Email address", "Password", "Continue").
 */
(function () {
  "use strict";

  var ACCOUNTS_KEY = "fakeClerk.accounts";
  var TOKEN_PREFIX = "fake-clerk.";

  function readAccounts() {
    try { return JSON.parse(localStorage.getItem(ACCOUNTS_KEY) || "{}"); } catch (_e) { return {}; }
  }

  function writeAccounts(accounts) { localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(accounts)); }

  // Deterministic user id per email (FNV-1a, two seeds) -> "user_<16 hex chars>"
  function userIdFor(email) {
    function fnv(str, seed) {
      var hash = seed >>> 0;
      for (var i = 0; i < str.length; i++) {
        hash ^= str.charCodeAt(i);
        hash = Math.imul(hash, 16777619) >>> 0;
      }
      return ("00000000" + hash.toString(16)).slice(-8);
    }
    var normalized = email.trim().toLowerCase();
    return "user_" + fnv(normalized, 2166136261) + fnv(normalized, 3735928559);
  }

  function readSessionCookie() {
    var match = document.cookie.match(/(?:^|;\s*)__session=([^;]+)/);
    return match ? decodeURIComponent(match[1]) : null;
  }

  function writeSessionCookie(userId) {
    document.cookie = "__session=" + encodeURIComponent(TOKEN_PREFIX + userId) + "; path=/; SameSite=Lax";
  }

  function clearSessionCookie() {
    document.cookie = "__session=; path=/; Max-Age=0; SameSite=Lax";
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (key) {
      if (key === "text") node.textContent = attrs[key];
      else node.setAttribute(key, attrs[key]);
    });
    (children || []).forEach(function (child) { node.appendChild(child); });
    return node;
  }

  function field(id, label, type, autocomplete) {
    return el("div", { class: "fake-clerk__field" }, [
      el("label", { for: id, text: label }),
      el("input", { id: id, name: id, type: type, required: "required", autocomplete: autocomplete })
    ]);
  }

  function buildForm(title, onSubmit) {
    var error = el("p", { class: "fake-clerk__error", role: "alert", "data-testid": "clerk-error" });
    var form = el("form", { class: "fake-clerk", novalidate: "novalidate" }, [
      el("h2", { text: title }),
      field("emailAddress", "Email address", "email", "email"),
      field("password", "Password", "password", "current-password"),
      error,
      el("button", { type: "submit", class: "btn", text: "Continue" })
    ]);
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      error.textContent = "";
      var email = form.querySelector("#emailAddress").value.trim().toLowerCase();
      var password = form.querySelector("#password").value;
      var message = onSubmit(email, password);
      if (message) error.textContent = message;
    });
    return form;
  }

  var style = document.createElement("style");
  style.textContent =
    ".fake-clerk{background:#fff;border:1px solid #e7e5ef;border-radius:14px;padding:24px;width:100%;max-width:380px;text-align:left;box-shadow:0 10px 30px rgba(29,27,44,.08)}" +
    ".fake-clerk h2{margin:0 0 16px;font-size:1.1rem}.fake-clerk__field{display:flex;flex-direction:column;gap:4px;margin-bottom:12px}" +
    ".fake-clerk__field input{padding:9px 10px;border:1px solid #cfcbe0;border-radius:8px;font:inherit}" +
    ".fake-clerk__error{color:#c03221;min-height:1.2em;margin:0 0 8px;font-size:.9rem}.fake-clerk .btn{width:100%;justify-content:center}";
  document.head.appendChild(style);

  var Clerk = {
    isFake: true,
    loaded: false,
    user: null,
    session: null,

    load: function () {
      var token = readSessionCookie();
      var accounts = readAccounts();
      this.user = null;
      this.session = null;
      if (token && token.indexOf(TOKEN_PREFIX) === 0) {
        var userId = token.slice(TOKEN_PREFIX.length);
        var email = Object.keys(accounts).find(function (key) { return accounts[key].id === userId; });
        this._setUser(userId, email || null);
      }
      this.loaded = true;
      return Promise.resolve();
    },

    _setUser: function (userId, email) {
      this.user = { id: userId, primaryEmailAddress: email ? { emailAddress: email } : null };
      this.session = {
        id: "sess_fake_" + userId.replace("user_", ""),
        getToken: function () { writeSessionCookie(userId); return Promise.resolve(TOKEN_PREFIX + userId); }
      };
    },

    _signIn: function (userId, email, redirectUrl) {
      this._setUser(userId, email);
      writeSessionCookie(userId);
      window.location.assign(redirectUrl || "/");
    },

    mountSignIn: function (node, options) {
      var self = this;
      node.innerHTML = "";
      node.appendChild(buildForm("Sign in to Billetto Events", function (email, password) {
        if (!email || !password) return "Enter your email address and password.";
        var account = readAccounts()[email];
        if (!account) return "Couldn't find your account.";
        if (account.password !== password) return "Password is incorrect. Try again.";
        self._signIn(account.id, email, options && (options.forceRedirectUrl || options.fallbackRedirectUrl));
        return null;
      }));
    },

    mountSignUp: function (node, options) {
      var self = this;
      node.innerHTML = "";
      node.appendChild(buildForm("Create your account", function (email, password) {
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return "Enter a valid email address.";
        if (password.length < 8) return "Passwords must be 8 characters or more.";
        var accounts = readAccounts();
        if (accounts[email]) return "That email address is taken. Please try another.";
        var userId = userIdFor(email);
        accounts[email] = { id: userId, password: password };
        writeAccounts(accounts);
        self._signIn(userId, email, options && (options.forceRedirectUrl || options.fallbackRedirectUrl));
        return null;
      }));
    },

    mountUserButton: function () {},

    signOut: function (options) {
      clearSessionCookie();
      this.user = null;
      this.session = null;
      window.location.assign((options && options.redirectUrl) || "/");
      return Promise.resolve();
    }
  };

  window.Clerk = Clerk;
})();

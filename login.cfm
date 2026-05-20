<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>MyUHCO — Sign In</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">

  <link rel="stylesheet" href="/assets/css/dist/myuhco/portal.css">
  <link rel="shortcut icon" href="assets/images/46904E6A-93E9-1182-D5CC96AA4A79783F.png">
</head>

<body id="MyUHCO">

  <div class="d-flex align-items-center justify-content-center min-vh-100">
  <div class="portal-login-card">
    <div class="text-center mb-4">
      <img
        src="assets/images/optopmetry-college-of-optometry-tertiary.svg"
        class="img-fluid"
        style="max-height:54px"
        alt="University of Houston College of Optometry">
    </div>

    <div class="card shadow-sm border-0">
      <div class="card-body p-4">

        <h4 class="text-center mb-4 fw-semibold">MyUHCO Sign In</h4>

        <div id="loginStatus" class="alert alert-info d-none" role="status" aria-live="polite"></div>

        <cfif structKeyExists(url, "error") AND len(trim(url.error))>
          <cfoutput>
          <div class="alert alert-danger" role="alert">
            #encodeForHTML(url.error)#
          </div>
          </cfoutput>
        </cfif>

        <form id="loginForm" method="post" action="authenticate.cfm" class="needs-validation" novalidate>

          <div class="mb-3">
            <label for="username" class="form-label">COUGARNET ID</label>
            <input
              type="text"
              class="form-control"
              id="username"
              name="username"
              autocomplete="username"
              required>
            <div class="invalid-feedback">Please enter your CougarNet ID.</div>
          </div>

          <div class="mb-3">
            <label for="password" class="form-label">PASSWORD</label>
            <div class="input-group">
              <input
                type="password"
                class="form-control"
                id="password"
                name="password"
                autocomplete="current-password"
                required>
              <button
                class="btn btn-secondary"
                type="button"
                id="togglePassword"
                aria-label="Show password">
                Show
              </button>
              <div class="invalid-feedback">Please enter your password.</div>
            </div>
          </div>

          <div class="d-grid">
            <button id="signInButton" type="submit" class="btn btn-primary">Sign In</button>
          </div>

        </form>

      </div>
    </div>
  </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  <script>
    // Form validation
    (function () {
      'use strict';
      var forms = document.querySelectorAll('.needs-validation');
      Array.prototype.slice.call(forms).forEach(function (form) {
        form.addEventListener('submit', function (event) {
          if (!form.checkValidity()) {
            event.preventDefault();
            event.stopPropagation();
          }
          form.classList.add('was-validated');
        }, false);
      });
    })();

    // Password toggle
    document.getElementById('togglePassword').addEventListener('click', function () {
      var input = document.getElementById('password');
      var isPassword = input.type === 'password';
      input.type = isPassword ? 'text' : 'password';
      this.textContent = isPassword ? 'Hide' : 'Show';
    });

    // Two-step AJAX login flow
    (function () {
      var form = document.getElementById('loginForm');
      var statusBox = document.getElementById('loginStatus');
      var signInButton = document.getElementById('signInButton');

      function readField(obj, key) {
        if (!obj) {
          return '';
        }
        if (Object.prototype.hasOwnProperty.call(obj, key)) {
          return obj[key];
        }
        var upperKey = key.toUpperCase();
        if (Object.prototype.hasOwnProperty.call(obj, upperKey)) {
          return obj[upperKey];
        }
        return '';
      }

      function setStatus(message, alertClass) {
        statusBox.className = 'alert ' + alertClass;
        statusBox.textContent = message;
        statusBox.classList.remove('d-none');
      }

      function setSubmitting(isSubmitting) {
        signInButton.disabled = isSubmitting;
        signInButton.textContent = isSubmitting ? 'Please wait...' : 'Sign In';
      }

      function postStep(payload) {
        return fetch('authenticate.cfm', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
          },
          body: new URLSearchParams(payload)
        }).then(function (response) {
          return response.json();
        });
      }

      form.addEventListener('submit', function (event) {
        if (!form.checkValidity()) {
          return;
        }

        event.preventDefault();

        var username = document.getElementById('username').value;
        var password = document.getElementById('password').value;

        setSubmitting(true);
        setStatus('Authenticating your account...', 'alert-info');

        postStep({
          ajaxStep: 'auth',
          username: username,
          password: password
        })
          .then(function (authResult) {
            if (!readField(authResult, 'success')) {
              throw new Error(readField(authResult, 'message') || 'Sign in failed.');
            }

            var displayName = readField(authResult, 'displayName') || username;
            setStatus('Welcome ' + displayName + '. Getting your profile...', 'alert-info');

            return postStep({
              ajaxStep: 'profile'
            });
          })
          .then(function (profileResult) {
            if (!readField(profileResult, 'success')) {
              throw new Error(readField(profileResult, 'message') || 'Could not load your profile.');
            }

            setStatus('Profile loaded. Redirecting...', 'alert-success');
            window.location.href = readField(profileResult, 'redirect') || 'index.cfm';
          })
          .catch(function (error) {
            setStatus(error.message || 'An unexpected error occurred.', 'alert-danger');
            setSubmitting(false);
          });
      });
    })();
  </script>
</body>
</html>

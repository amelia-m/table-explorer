      document.addEventListener("DOMContentLoaded", function() {
        // Theme toggle
        var btn = document.getElementById("theme-toggle");
        if (btn) {
          btn.addEventListener("click", function() {
            document.body.classList.toggle("light-mode");
            var isLight = document.body.classList.contains("light-mode");
            document.getElementById("toggle-label").textContent = isLight ? "Dark mode" : "Light mode";
          });
        }
        // Per-table remove buttons (delegated - buttons are rendered dynamically)
        document.body.addEventListener("click", function(e) {
          if (e.target.classList.contains("btn-remove")) {
            Shiny.setInputValue("remove_table_name", e.target.dataset.tname, {priority: "event"});
          }
        });
        // Scan triage modal: lock the choice instantly. The server can be busy
        // for a while after a large upload, so without this the modal stays
        // clickable and users click again or pick a second option.
        document.body.addEventListener("click", function(e) {
          var clicked = e.target.closest(".triage-btn");
          if (!clicked) return;
          var modal = clicked.closest(".modal-content") || document;
          modal.querySelectorAll(".triage-btn").forEach(function(b) {
            b.disabled = true;
            b.style.opacity = b === clicked ? "1" : "0.4";
            b.style.cursor = "wait";
          });
          var status = modal.querySelector(".triage-status");
          if (status) {
            status.textContent = clicked.id.endsWith("triage_skip")
              ? "\u23f3 Skipping auto-detection\u2026"
              : "\u23f3 Starting scan\u2026 this can take a moment while tables finish loading.";
            status.style.display = "block";
          }
        });
        // Sticky node panel close button
        document.body.addEventListener("click", function(e) {
          if (e.target.id === "node-panel-close") {
            document.getElementById("node-panel-overlay").style.display = "none";
            Shiny.setInputValue("vis_close_panel", Math.random(), {priority: "event"});
          }
        });
        // Light mode: flip node panel to light
        var observer = new MutationObserver(function() {
          var panel = document.getElementById("node-panel-overlay");
          if (!panel) return;
          if (document.body.classList.contains("light-mode")) {
            panel.style.background = "#ffffff";
            panel.style.borderColor = "#cbd5e1";
            panel.style.color = "#0f172a";
          } else {
            panel.style.background = "#0f172a";
            panel.style.borderColor = "#1e3a5f";
            panel.style.color = "#e2e8f0";
          }
        });
        observer.observe(document.body, {attributes: true, attributeFilter: ["class"]});
      });
      // Called by visNetwork click event via Shiny.setInputValue
      function showNodePanel(nodeId) {
        if (!nodeId) return;
        var panel = document.getElementById("node-panel-overlay");
        if (panel) panel.style.display = "block";
      }

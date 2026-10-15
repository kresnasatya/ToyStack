window.addEventListener("message", function (e) {
  window.console.log("Message received from iframe: " + e.data);
  var log = document.getElementById("log");
  log.innerHTML += "<p>[received] " + e.data + "</p>";
});

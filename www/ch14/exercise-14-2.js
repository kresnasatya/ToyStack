var log = document.getElementById("event-log");

function report(msg) {
  log.innerHTML = msg;
  console.log(msg);
}

function watch(id, label) {
  var elt = document.getElementById(id);
  elt.addEventListener("focus", function () {
    report(label + ": focus");
  });
  elt.addEventListener("blur", function () {
    report(label + ": blur");
  });
  return elt;
}

var nameInput = watch("name", "name input");
var tabindexDiv = watch("tabindex-div", "tabindex div");
var plainDiv = watch("plain-div", "plain div"); // must never fire
var farInput = watch("far", "far input");

document.getElementById("focus-name").addEventListener("click", function () {
  nameInput.focus();
});

document.getElementById("focus-plain").addEventListener("click", function () {
  plainDiv.focus(); // not focusable: must be a no-op
});

document
  .getElementById("focus-tabindex")
  .addEventListener("click", function () {
    tabindexDiv.focus();
  });

document.getElementById("focus-far").addEventListener("click", function () {
  farInput.focus(); // scrolls: position read after layout is up to date
});

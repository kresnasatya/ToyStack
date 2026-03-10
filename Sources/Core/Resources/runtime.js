console = {
  log: function (x) {
    _log(x);
  },
};

document = {
  querySelectorAll: function (s) {
    var handles = _querySelectorAll(s);
    return handles.map(function (h) {
      return Node(h);
    });
  },
};

Node.prototype.getAttribute = function (attr) {
  return _getAttribute(this.handle, attr);
};

Object.defineProperty(Node.prototype, "innerHTML", {
  set: function (s) {
    _innerHTML(this.handle, s.toString());
  },
});

XMLHttpRequest.prototype.send = function (body) {
  this.responseText = _XHRSend(this.method, this.url, body);
};

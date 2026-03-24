var __globalThis = this;

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
  createElement: function (tag) {
    var handle = _createElement(tag);
    return new Node(handle);
  },
};

Object.defineProperty(document, "cookie", {
  get: function () {
    return _getCookie();
  },
  set: function (s) {
    _setCookie(s.toString());
  },
});

function Node(handle) {
  this.handle = handle;
}

Node.prototype.getAttribute = function (attr) {
  return _getAttribute(this.handle, attr);
};

Node.prototype.appendChild = function (child) {
  _appendChild(this.handle, child.handle);
};

Node.prototype.insertBefore = function (child, ref) {
  _insertBefore(this.handle, child.handle, ref.handle);
};

Node.prototype.removeChild = function (child) {
  var handle = _removeChild(this.handle, child.handle);
  return new Node(handle);
};

Node.prototype.setAttribute = function (attr, value) {
  _setAttribute(this.handle, attr, value.toString());
};

var LISTENERS = {};

Node.prototype.addEventListener = function (type, listener) {
  if (!LISTENERS[this.handle]) LISTENERS[this.handle] = {};
  var dict = LISTENERS[this.handle];
  if (!dict[type]) dict[type] = [];
  var list = dict[type];
  list.push(listener);
};

Node.prototype.dispatchEvent = function (evt) {
  var type = evt.type;
  var handle = this.handle;
  var list = (LISTENERS[handle] && LISTENERS[handle][type]) || [];
  for (var i = 0; i < list.length; i++) {
    list[i].call(this, evt);
  }
  if (!evt.stop_propagation) {
    var parentHandle = _getParent(this.handle);
    if (parentHandle !== -1) {
      new Node(parentHandle).dispatchEvent(evt);
    }
  }
  return evt.do_default;
};

Object.defineProperty(Node.prototype, "id", {
  get: function () {
    return _getAttribute(this.handle, "id");
  },
  set: function (value) {
    _setAttribute(this.handle, "id", value.toString());
  },
});

Object.defineProperty(Node.prototype, "innerHTML", {
  get: function () {
    return _serializeInner(this.handle);
  },
  set: function (s) {
    _innerHTML(this.handle, s.toString());
    __defineIDs(); // re-scan after DOM changes
  },
});

Object.defineProperty(Node.prototype, "outerHTML", {
  get: function () {
    return _serializeOuter(this.handle);
  },
});

Object.defineProperty(Node.prototype, "children", {
  get: function () {
    var handles = _children(this.handle);
    return handles.map(function (h) {
      return new Node(h);
    });
  },
});

function Event(type) {
  this.type = type;
  this.do_default = true;
  this.stop_propagation = false;
}

Event.prototype.preventDefault = function () {
  this.do_default = false;
};

Event.prototype.stopPropagation = function () {
  this.stop_propagation = true;
};

function XMLHttpRequest() {}

XMLHttpRequest.prototype.open = function (method, url, is_async) {
  if (is_async) throw Error("Asynchronous XHR is not supported");
  this.method = method;
  this.url = url;
};

XMLHttpRequest.prototype.send = function (body) {
  this.responseText = _XHRSend(this.method, this.url, body);
};

function __defineIDs() {
  var ids = _getIDs();
  for (var id in ids) {
    __globalThis[id] = new Node(ids[id]);
  }
}

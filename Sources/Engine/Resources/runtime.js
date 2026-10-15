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
      return new Node(h);
    });
  },
  getElementById: function (id) {
    var ids = _getIDs();
    var handle = ids[id];
    if (handle === undefined) return null;
    return new Node(handle);
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

  var attr = this.getAttribute("on" + type);
  if (attr) {
    var handler = new Function("event", attr);
    handler.call(this, evt);
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
    __defineIDs();
  },
});

Object.defineProperty(Node.prototype, "outerHTML", {
  get: function () {
    return _serializeOuter(this.handle);
  },
});

Object.defineProperty(Node.prototype, "textContent", {
  get: function () {
    return _getTextContent(this.handle);
  },
  set: function (s) {
    _setTextContent(this.handle, s.toString());
  }
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

Object.defineProperty(Node.prototype, "style", {
  get: function () {
    var handle = this.handle;
    return new Proxy(
      {},
      {
        set: function (target, attr, value) {
          __styleSet__(handle, attr, value.toString());
          return true;
        },
      },
    );
  },
  set: function (value) {
    _setAttribute(this.handle, "style", value.toString());
  },
});

Object.defineProperty(Node.prototype, "scrollTop", {
  set: function (value) {
    _setScrollTop(this.handle, value);
  },
});

Node.prototype.focus = function () {
  _focusElement(this.handle);
};

Node.prototype.getContext = function (type) {
  if (type !== "2d") return null;
  if (!_canvasContext(this.handle, type)) return null;
  return new CanvasRenderingContext2D(this.handle);
};

function CanvasRenderingContext2D(handle) {
  this.handle = handle;
}

Object.defineProperty(CanvasRenderingContext2D.prototype, "fillStyle", {
  get: function () {
    return paintFromStored(this.handle, _canvasStyleGet(this.handle, "fillStyle"));
  },
  set: function (value) {
    _canvasStyleSet(this.handle, "fillStyle", value.toString());
  }
});

Object.defineProperty(CanvasRenderingContext2D.prototype, "strokeStyle", {
  get: function () {
    return paintFromStored(this.handle, _canvasStyleGet(this.handle, "strokeStyle"));
  },
  set: function (value) {
    _canvasStyleSet(this.handle, "strokeStyle", value.toString());
  }
});

Object.defineProperty(CanvasRenderingContext2D.prototype, "lineWidth", {
  get: function () {
    return parseFloat(_canvasStyleGet(this.handle, "lineWidth"));
  },
  set: function (value) {
    _canvasStyleSet(this.handle, "lineWidth", value.toString());
  }
});

Object.defineProperty(CanvasRenderingContext2D.prototype, "font", {
  get: function () {
    return _canvasStyleGet(this.handle, "font");
  },
  set: function (value) {
    _canvasStyleSet(this.handle, "font", value.toString());
  }
});

CanvasRenderingContext2D.prototype.fillRect = function (x, y, w, h) {
  _canvasRect(this.handle, "fill", [x, y, w, h]);
}

CanvasRenderingContext2D.prototype.clearRect = function (x, y, w, h) {
  _canvasRect(this.handle, "clear", [x, y, w, h]);
}

CanvasRenderingContext2D.prototype.strokeRect = function (x, y, w, h) {
  _canvasRect(this.handle, "stroke", [x, y, w, h]);
}

CanvasRenderingContext2D.prototype.beginPath = function () {
  _canvasPath(this.handle, "begin", []);
}

CanvasRenderingContext2D.prototype.moveTo = function (x, y) {
  _canvasPath(this.handle, "move", [x, y]);
}

CanvasRenderingContext2D.prototype.lineTo = function (x, y) {
  _canvasPath(this.handle, "line", [x, y]);
}

CanvasRenderingContext2D.prototype.stroke = function () {
  _canvasPaint(this.handle, "stroke");
}

CanvasRenderingContext2D.prototype.fill = function () {
  _canvasPaint(this.handle, "fill");
}

CanvasRenderingContext2D.prototype.fillText = function (text, x, y) {
  _canvasText(this.handle, text.toString(), [x, y]);
}

CanvasRenderingContext2D.prototype.save = function () {
  _canvasState(this.handle, "save");
}

CanvasRenderingContext2D.prototype.restore = function () {
  _canvasState(this.handle, "restore");
}

CanvasRenderingContext2D.prototype.translate = function (x, y) {
  _canvasTransform(this.handle, "translate", [x, y]);
}

CanvasRenderingContext2D.prototype.scale = function (x, y) {
  _canvasTransform(this.handle, "scale", [x, y]);
}

CanvasRenderingContext2D.prototype.rotate = function (angle) {
  _canvasTransform(this.handle, "rotate", [angle]);
}

CanvasRenderingContext2D.prototype.transform = function (a, b, c, d, e, f) {
  _canvasTransform(this.handle, "transform", [a, b, c, d, e, f]);
}

CanvasRenderingContext2D.prototype.setTransform = function(a, b, c, d, e, f) {
  _canvasTransform(this.handle, "setTransform", [a, b, c, d, e, f]);
}

CanvasRenderingContext2D.prototype.resetTransform = function () {
  _canvasTransform(this.handle, "reset", []);
}

CanvasRenderingContext2D.prototype.drawImage = function (image) {
  var source = image && image.handle;
  if (source === undefined || source === null) return;
  var nums = Array.prototype.slice.call(arguments, 1).map(Number);
  var mode = null;
  if (nums.length === 2) {
    mode = "at";
  } else if (nums.length === 4) {
    mode = "scale";
  } else if (nums.length === 8) {
    mode = "crop";
  }
  if (mode === null) return;
  _canvasDrawImage(this.handle, source, mode, nums);
}

function CanvasGradient(handle, id) {
  this.handle = handle;
  this.id = id;
}

CanvasGradient.prototype.addColorStop = function (offset, color) {
  var error = _canvasGradientStop(this.handle, this.id, Number(offset), color.toString());
  if (error) {
    var e = new Error(error);
    e.name = error;
    throw e;
  }
}

CanvasGradient.prototype.toString = function () {
  return "--gradient--" + this.id;
}

function paintFromStored(handle, stored) {
  if (stored.indexOf("--gradient--") === 0) {
    return new CanvasGradient(handle, parseInt(stored.slice(12), 10));
  }
  return stored;
}

CanvasRenderingContext2D.prototype.createLinearGradient = function (x0, y0, x1, y1) {
  var id = _canvasCreateGradient(this.handle, "linear", [x0, y0, x1, y1]);
  return id < 0 ? null : new CanvasGradient(this.handle, id);
}

CanvasRenderingContext2D.prototype.createRadialGradient = function (x0, y0, r0, x1, y1, r1) {
  var id = _canvasCreateGradient(this.handle, "radial", [x0, y0, r0, x1, y1, r1]);
  return id < 0 ? null : new CanvasGradient(this.handle, id);
}

var __RAFHandlers = [];

function __runRAFHandlers() {
  var handlers = __RAFHandlers;
  __RAFHandlers = [];
  for (var i = 0; i < handlers.length; i++) {
    handlers[i]();
  }
}

function Window(id) {
  this._id = id;
}

var WINDOWS = {};

var location = {};

Object.defineProperty(location, "href", {
  get: function () {
    return _getLocationHref();
  },
  set: function (value) {
    _setLocationHref(value.toString());
  }
});

Object.defineProperty(location, "hash", {
  get: function () {
    var href = _getLocationHref();
    var index = href.indexOf("#");
    return index === -1 ? "" : href.slice(index);
  },
  set: function (value) {
    var hash = value.toString();
    if (hash.charAt(0) !== "#") hash = "#" + hash;
    _setLocationHref(hash);
  }
});

window = new Window(_getWindowID());
WINDOWS[window._id] = window;

window.console = console;
window.document = document;
window.Node = Node;
window.Event = Event;
window.XMLHttpRequest = XMLHttpRequest;
window.MessageEvent = MessageEvent;

Object.defineProperty(window, "origin", {
  get: function () {
    return _getOrigin();
  }
});

window.WINDOW_LISTENERS = {};

Window.prototype.addEventListener = function (type, listener) {
  if (!window.WINDOW_LISTENERS[this._id]) window.WINDOW_LISTENERS[this._id] = {};
  var dict = window.WINDOW_LISTENERS[this._id];
  if (!dict[type]) dict[type] = [];
  dict[type].push(listener);
}

Window.prototype.dispatchEvent = function (event) {
  var dict = window.WINDOW_LISTENERS[this._id];
  var list = (dict && dict[event.type]) || [];
  for (var i = 0; i < list.length; i++) {
    list[i].call(this, event);
  }
  return event.do_default;
}

Window.prototype.postMessage = function (message, targetOrigin) {
  _postMessage(this._id, message.toString(), targetOrigin.toString());
}

Object.defineProperty(Window.prototype, "parent", {
  configurable: true,
  get: function () {
    var parentID = _parent(this._id);
    if (parentID === -1) return undefined;
    var parent = WINDOWS[parentID];
    if (parent === undefined) parent = new Window(parentID);
    return parent;
  },
});

function MessageEvent(data) {
  this.type = "message";
  this.data = data;
  this.do_default = true;
}

function requestAnimationFrame(callback) {
  __RAFHandlers.push(callback);
  _requestAnimationFrame();
}

window.requestAnimationFrame = requestAnimationFrame;

SET_TIMEOUT_REQUESTS = {};

function setTimeout(callback, time_delta) {
  var handle = Object.keys(SET_TIMEOUT_REQUESTS).length;
  SET_TIMEOUT_REQUESTS[handle] = callback;
  __setTimeout(handle, time_delta);
}

function __runSetTimeout(handle) {
  var callback = SET_TIMEOUT_REQUESTS[handle];
  if (callback) callback();
}

var SET_INTERVAL_REQUESTS = {};
var __intervalHandleCounter = 0;

function setInterval(callback, time_delta) {
  var handle = __intervalHandleCounter++;
  SET_INTERVAL_REQUESTS[handle] = callback;
  __setInterval(handle, time_delta);
  return handle;
}

function clearInterval(handle) {
  delete SET_INTERVAL_REQUESTS[handle];
  __clearInterval(handle);
}

function __runSetInterval(handle) {
  var callback = SET_INTERVAL_REQUESTS[handle];
  if (callback) callback();
}

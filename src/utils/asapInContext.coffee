((factory) ->
  isBrowser = typeof window != 'undefined' and window.document
  rootCtx = if isBrowser then window else global
  if typeof module == 'object' and typeof module.exports == 'object'
    # CommonJS
    module.exports = factory(rootCtx)
  else if typeof define == 'function' and define.amd
    # AMD. Register as an anonymous module.
    define -> factory(rootCtx)
  else
    # Browser globals
    rootCtx.rawAsap = factory(rootCtx)
)((global) ->
  ###
  Asap library port with ability to provide context object in which callback should be run to avoid creation of closures.
  ###

  queue = []
  # Once a flush has been requested, no further calls to `requestFlush` are
  # necessary until the next `flush` completes.
  flushing = false
  # `requestFlush` is an implementation-specific method that attempts to kick
  # off a `flush` event as quickly as possible. `flush` will attempt to exhaust
  # the event queue before yielding to the browser's own event loop.
  requestFlush = undefined
  # The position of the next task to execute in the task queue. This is
  # preserved between calls to `flush` so that it can be resumed if
  # a task throws an exception.
  index = 0
  # If a task schedules additional tasks recursively, the task queue can grow
  # unbounded. To prevent memory exhaustion, the task queue will periodically
  # truncate already-completed tasks.
  capacity = 1024


  flush = ->
    ###
    The flush function processes all tasks that have been scheduled with
    `rawAsap` unless and until one of those tasks throws an exception.
    If a task throws an exception, `flush` ensures that its state will remain
    consistent and will resume where it left off when called again.
    However, `flush` does not make any arrangements to be called again if an
    exception is thrown.
    ###
    while index < queue.length
      currentIndex = index
      # Advance the index before calling the task. This ensures that we will
      # begin flushing on the next task the task throws an error.
      index = index + 2;
      queue[currentIndex].call(queue[currentIndex + 1])
      # Prevent leaking memory for long chains of recursive calls to `asap`.
      # If we call `asap` within tasks scheduled by `asap`, the queue will
      # grow, but to avoid an O(n) walk for every task we execute, we don't
      # shift tasks off the queue after they have been executed.
      # Instead, we periodically shift 1024 tasks off the queue.
      if index > capacity
        # Manually shift all values starting at the index back to the
        # beginning of the queue.
        scan = 0
        len = queue.length - index
        while scan < len
          queue[scan] = queue[scan + index]
          scan++
        queue.length -= index
        index = 0
    queue.length = 0
    index = 0
    flushing = false


  makeRequestCallFromMutationObserver = (callback) ->
    ###
    To request a high priority event, we induce a mutation observer by toggling
    the text of a text node between "1" and "-1".
    ###
    toggle = 1
    observer = new BrowserMutationObserver(callback)
    node = document.createTextNode('')
    observer.observe(node, characterData: true)
    ->
      toggle = -toggle
      node.data = toggle


  makeRequestCallFromTimer = (callback) ->
    ###
    `setTimeout` does not call the passed callback if the delay is less than
    approximately 7 in web workers in Firefox 8 through 18, and sometimes not
    even then.
    ###
    ->
      handleTimer = ->
        # Whichever timer succeeds will cancel both timers and
        # execute the callback.
        clearTimeout(timeoutHandle)
        clearInterval(intervalHandle)
        callback()
      # We dispatch a timeout with a specified delay of 0 for engines that
      # can reliably accommodate that request. This will usually be snapped
      # to a 4 milisecond delay, but once we're flushing, there's no delay
      # between events.
      timeoutHandle = setTimeout(handleTimer, 0)
      # However, since this timer gets frequently dropped in Firefox
      # workers, we enlist an interval handle that will try to fire
      # an event 20 times per second until it succeeds.
      intervalHandle = setInterval(handleTimer, 50)


  if typeof window != 'undefined' and window.document
    # Browser
    BrowserMutationObserver = window.MutationObserver or window.WebKitMutationObserver
    if typeof BrowserMutationObserver == 'function'
      requestFlush = makeRequestCallFromMutationObserver(flush)
    else
      requestFlush = makeRequestCallFromTimer(flush)
  else
    # NodeJS
    hasSetImmediate = typeof setImmediate == 'function'
    requestFlush = ->
      # Ensure flushing is not bound to any domain.
      # It is not sufficient to exit the domain, because domains exist on a stack.
      # To execute code outside of any domain, the following dance is necessary.
      parentDomain = process.domain
      if parentDomain
        if not domain
          # Lazy execute the domain module.
          # Only employed if the user elects to use domains.
          domain = require('domain')
        domain.active = process.domain = null

      # `setImmediate` is slower that `process.nextTick`, but `process.nextTick`
      # cannot handle recursion.
      # `requestFlush` will only be called recursively from `asap.js`, to resume
      # flushing after an error is thrown into a domain.
      # Conveniently, `setImmediate` was introduced in the same version
      # `process.nextTick` started throwing recursion errors.
      if flushing and hasSetImmediate
        setImmediate(flush)
      else
        process.nextTick(flush)

      if parentDomain
        domain.active = process.domain = parentDomain


  (ctx, task) ->
    ###
    asapInContext function.
    @param {Object} ctx - context object which will be `this` for the callback
    @param {Function} task - callback function that is added to the high-priority queue
    ###
    if not queue.length
      requestFlush()
      flushing = true
    # Equivalent to push, but avoids a function call.
    queue[queue.length] = task
    queue[queue.length] = ctx
    return
)

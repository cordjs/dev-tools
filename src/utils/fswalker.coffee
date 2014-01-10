fs   = require 'fs'
path = require 'path'
{EventEmitter} = require 'events'
_    = require 'underscore'

Future = require './Future'


class FsWalker extends EventEmitter
  ###
  Simple implementation of recursive file-system walker using async Futures.
  The class emits events with the same semantics as npm walk library.
  Additionally it has filter-function support to avoid walking throught unnecessary directories.
  ###

  _filterFn: null

  _itemQueue: null
  _active: false # is some event being emitted
  _scanFinished: false


  constructor: (dir, options) ->
    if options?
      @_filterFn = if _.isFunction(options.filter) then options.filter else -> true

    @_itemQueue = []
    @_walk(dir).failAloud().done =>
      @_scanFinished = true
      @emit 'end' if not @_active


  _walk: (root, name) ->
    ###
    @param String root absolute path to the directory containing item to be scanned
    @param String name local name of the file or directory to be scanned
    @return Future completed when the given FS item is scanned and added to the event-emitter queue
    ###
    target = if name then path.join(root, name) else root
    Future.call(fs.lstat, target).flatMap (stat) =>
      stat.name = name
      if stat.isDirectory()
        Future.call(fs.readdir, target).flatMap (items) =>
          futures = (@_walk(target, item) for item in items when @_filterFn(target, item))
          @_add('directory', root, stat) if name # not adding base directory
          Future.sequence(futures)
      else if stat.isSymbolicLink()
        @_add('symbolicLink', root, stat)
        Future.resolved()
      else if stat.isFile()
        @_add('file', root, stat)
        Future.resolved()
      else
        # ignoring unusual file types
        Future.resolved()
    # ignore suddenly removed files
    .flatMapFail (err) ->
      if err.code == 'ENOENT'
        Future.resolved()
      else
        Future.rejected(err)


  _add: (type, root, stat) ->
    @_itemQueue.push([type, root, stat])
    @_next() if not @_active # initiate event-emitter chain if it's not active


  _next: => # fat-arrow is necessary here!
    ###
    Chained event-emitter. Passed to every event callback and must be called by the handler in order to continue
     emitting.
    ###
    while true
      item = @_itemQueue.shift()
      if item?
        [type, root, stat] = item
        if EventEmitter.listenerCount(this, type)
          @_active = true
          @emit type, root, stat, @_next
        else
          # if threre are no listeners, next() will never be called, so jump to the next item immediately
          continue
      else
        @_active = false
        @emit 'end' if @_scanFinished
      break



module.exports = (dir, options) ->
  new FsWalker(dir, options)

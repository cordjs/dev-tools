{spawn} = require 'child_process'
path    = require 'path'
util    = require 'util'


class ServerProcessManager
  ###
  Manages cordjs development web-server process starting/stopping/restarting
  ###

  _process: null
  _errorCounter: 0
  _resetErrorCounterTimeout: null

  constructor: (@params) ->


  start: ->
    if not @_process
      @_process = spawn 'node', [
        path.join(@params.targetDir, 'server.js')
        path.join(@params.targetDir, 'public')
        @params.config
        @params.port
      ], {cwd: @params.targetDir}

      @_process.stdout.on('data', util.print)
      @_process.stderr.on('data', util.print)

      @_process.on 'exit', (code) =>
        if @_errorCounter > 1
          util.log "Too many restart errors. Stopping to try. Error code '#{ code }'"
        else
          @_errorCounter++
          @restart()

      clearTimeout(@_resetErrorCounterTimeout) if @_resetErrorCounterTimeout?
      @_resetErrorCounterTimeout = setTimeout =>
        @_errorCounter = 0
      , 1000

    else
      console.warn "Server process is already started!"


  stop: ->
    if @_process
      @_process.removeAllListeners('exit')
      @_process.kill()
      @_process = null


  restart: ->
    @stop()
    @start()



module.exports = ServerProcessManager

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

      serverProcessArgs = []

      for arg in process.execArgv
        if 0 == arg.indexOf('--debug-brk=')
          currentPort = parseInt(arg.substring('--debug-brk='.length))
          if null != currentPort
            serverProcessArgs.push("--debug-brk=#{currentPort+1}")

      serverProcessArgs = serverProcessArgs.concat [
        path.join(@params.targetDir, 'server.js')
        path.join(@params.targetDir, 'public')
        @params.config
        @params.port
      ]

      serverProcessParams =
        cwd: @params.targetDir
        env: {}

      if @params.map
        serverProcessParams.env.DEV_SOURCES_SERVER_ROOT_DIR = @params.baseDir

      util.log "node #{serverProcessArgs.join(' ')}"
      @_process = spawn('node', serverProcessArgs, serverProcessParams)

      @_process.stdout.on('data', (x) -> process.stdout.write(x))
      @_process.stderr.on('data', (x) -> process.stderr.write(x))

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

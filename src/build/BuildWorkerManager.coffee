{fork} = require('child_process')
Future = require('../utils/Future')


class BuildWorkerManager
  ###
  Build worker process representation on the main build process side.
  ###

  # maximum number of unacknowleged tasks after which the worker stops accepting new tasks
  @MAX_SENDING_TASKS = 30000
  # number of milliseconds of idle state (without active tasks) after which the worker is auto-stopped
  @IDLE_STOP_TIMEOUT = 3000
  # worker id counter
  @_idCounter: 0
  # worker id (mostly for debugging purposes)
  id: 0
  # child process (in terms of nodejs)
  _process: null
  # Map[taskId, Future] of active task result futures to be able to notify build manager about task completion
  _tasks: null
  # how many tasks are sent to worker process but not acknowleged
  _sendingTask: 0
  # future that is resolved when this worker is ready to accept new tasks
  _acceptReady: null
  # current workload rate of the worker process
  _workload: 0
  # current number processing tasks
  _taskCounter: 0
  # counter of the tasks executed by this worker
  totalTasksCount: 0
  # timeout handle need to auto-stop the worker when idle
  _killTimeout: null
  _stopped: false

  constructor: (@manager) ->
    @id = ++BuildWorkerManager._idCounter
    @_process = fork(__dirname + '/build-worker.js')
    @_acceptReady = Future.resolved(this)
    @_tasks = {}
    # worker process communication callback
    @_process.on 'message', (m) =>
      switch m.type
        when 'completed'
          @_tasks[m.task].resolve()
          delete @_tasks[m.task]
          @_taskCounter--
          if @_taskCounter == 0 and not @_stopped
            @_killTimeout = setTimeout =>
              @stop() if @_taskCounter == 0
            , BuildWorkerManager.IDLE_STOP_TIMEOUT


  addTask: (taskParams) ->
    ###
    @return Future[Nothing]
    ###
    if @canAcceptTask()
      @_tasks[taskParams.id] = Future.single()
      @_process.send(taskParams)
      @_sendingTask++
      @_acceptReady = Future.single() if not @canAcceptTask()
      @_taskCounter++
      @totalTasksCount++
      clearTimeout(@_killTimeout) if @_killTimeout
      taskWorkload = @getTaskWorkload(taskParams)
      @_workload += taskWorkload
      @_tasks[taskParams.id].done =>
        @_workload -= taskWorkload
    else
      throw new Error("Can't accept task now!")


  getTaskWorkload: (taskParams) ->
    switch taskParams.info.ext
      when '.coffee' then 1
      when '.styl' then 1.1
      when '.js' then 0.2
      else 0


  stop: ->
    ###
    Kills worker process and stops this worker.
    ###
    clearTimeout(@_killTimeout) if @_killTimeout
    if not @_stopped
      @_process.kill()
      @manager.stopWorker(this)
      @_stopped = true


  canAcceptTask: -> @_sendingTask < BuildWorkerManager.MAX_SENDING_TASKS


  acceptReady: -> @_acceptReady


  getWorkload: -> @_workload



module.exports = BuildWorkerManager

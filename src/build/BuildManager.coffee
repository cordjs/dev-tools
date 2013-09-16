_ = require('underscore')
os = require('os')
{Future} = require('../utils/Future')
{BuildWorkerManager} = require('./BuildWorkerManager')


class BuildManager
  ###
  Build worker process manager and load balancer for the build tasks
  @static
  ###

  @workers: []
  @MAX_WORKERS: Math.max(os.cpus().length, 2)

  @_taskIdCounter: 0

  @createTask: (relativeFilePath, baseDir, targetDir, fileInfo) ->
    @findBestWorker().flatMap (worker) =>
      worker.addTask
        id: ++@_taskIdCounter
        file: relativeFilePath
        baseDir: baseDir
        targetDir: targetDir
        info: fileInfo


  @findBestWorker: ->
    ###
    Chooses best worker process (less loaded) for the next file.
    @return Future[Worker]
    ###
    result = Future.single()

    # firstly take worker without any workload
    emptyWorker = _.find @workers, (w) -> w.getWorkload() == 0
    if emptyWorker
      result.resolve(emptyWorker)
    else
      # secondly create a new worker process if there is a room according to settings
      if @workers.length < @MAX_WORKERS
        newWorker = new BuildWorkerManager(this)
        @workers.push(newWorker)
        result.resolve(newWorker)
      else
        # thirdly get the least loaded worker which can accept tasks at the moment
        freeWorkers = _.filter @workers, (w) -> w.canAcceptTask()
        if freeWorkers.length
          sorted = _.sortBy freeWorkers, (w) -> w.getWorkload()
          result.resolve(sorted[0])
        else
          # lastly, if all workers can't accept tasks now, wait for the first available worker
          # we should retry waiting because another task could tackle the worker
          recursiveWait = =>
            Future.select(_.map @workers, (w) -> w.acceptReady()).done (worker) ->
              if worker.canAcceptTask()
                result.resolve(worker)
              else
                recursiveWait()
          recursiveWait()

    result


  @stop: ->
    w.stop() for w in @workers


  @stopWorker: (worker) ->
    @workers = _.without(@workers, worker)
    console.log "Worker #{ worker.id } stopped. Total tasks count: #{ worker.totalTasksCount }"



exports.buildManager = BuildManager

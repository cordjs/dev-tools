_ = require('underscore')
os = require('os')
Future = require('../utils/Future')
BuildWorkerManager = require('./BuildWorkerManager')


MAX_WORKERS = Math.max(os.cpus().length, 2)
workers = []
taskIdCounter = 0

# {Array<Future<BuildWorkerQueue>>} queue of promises waiting for the free build worker
workerQueue = []
# processWorkerQueue function trigger flag
queueActivated = false


joinTheQueue = ->
  ###
  Creates a new promise, puts it to the queue and returns it.
  It'll be completed with the free build worker when the promise is first in the queue.
  @return {Future<BuildWorkerManager>}
  ###
  resultPromise = Future.single()
  workerQueue.push(resultPromise)
  processWorkerQueue()  if not queueActivated
  resultPromise


processWorkerQueue = ->
  ###
  Fulfills waiting promises from the queue with the free workers as they are getting free.
  Works until the queue is empty.
  ###
  queueActivated = true
  Future.any(workers.map (w) -> w.acceptReady()).then (worker) ->
    if worker.canAcceptTask()
      workerQueue.shift().resolve(worker)
    if workerQueue.length
      processWorkerQueue()
    else
      queueActivated = false
    return
  .failAloud('processWorkerQueue')
  return


findBestWorker = ->
  ###
  Chooses best worker process (less loaded) for the next file.
  @return {Future<BuildWorkerManager>}
  ###
  # firstly take worker without any workload
  emptyWorker = _.find workers, (w) -> w.getWorkload() == 0
  if emptyWorker
    Future.resolved(emptyWorker)
  else
    # secondly create a new worker process if there is a room according to settings
    if workers.length < MAX_WORKERS
      newWorker = new BuildWorkerManager(self)
      workers.push(newWorker)
      Future.resolved(newWorker)
    else
      # thirdly get the least loaded worker which can accept tasks at the moment
      freeWorkers = workers.filter (w) -> w.canAcceptTask()
      if freeWorkers.length
        sorted = _.sortBy freeWorkers, (w) -> w.getWorkload()
        Future.resolved(sorted[0])
      else
        # lastly, if all workers can't accept tasks now, wait for the first available worker
        joinTheQueue()


module.exports = self =
  ###
  Build worker process manager and load balancer for the build tasks
  @static
  ###

  generateSourceMap: false

  createTask: (relativeFilePath, baseDir, targetDir, fileInfo) ->
    ###
    Assigns a new task based on the given params to the free build worker
    @param {String} relativeFlePath - file to be built
    @param {String} baseDir - base dir of the building project
    @param {String} targetDir
    @param {Object} fileInfo - special precomputed file properties used by the build task
    @return {Future<undefined>} promise is complete when the build task is complete
    ###
    findBestWorker().then (worker) =>
      worker.addTask
        id: ++taskIdCounter
        file: relativeFilePath
        baseDir: baseDir
        targetDir: targetDir
        info: fileInfo
        generateSourceMap: @generateSourceMap
    .catch (err) =>
      if err.overwhelmed  # racing condition, just need to retry
        @createTask(relativeFilePath, baseDir, targetDir, fileInfo)
      else
        throw err


  stop: ->
    ###
    Immediately stops all build workers
    ###
    # for loop is not appropriate here because worker.stop() call implicitly modifies workers array.
    while workers.length
      workers[0].stop()
    return


  stopWorker: (worker) ->
    ###
    Removes the given worker from the workers array.
    Called from the build worker to consistently complete its stopping.
    @internal
    @param {BuildWorkerManager} worker
    ###
    workers = _.without(workers, worker)
    console.log "Worker #{ worker.id } stopped. Total tasks count: #{ worker.totalTasksCount }"  if false
    return

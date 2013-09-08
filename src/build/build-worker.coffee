###
Build worker process main script.
###
path = require('path')
_ = require('underscore')

{CompileCoffeeScript} = require('./task/CompileCoffeeScript')
{Fake} = require('./task/Fake')
{CopyFile} = require('./task/CopyFile')


class BuildWorker

  # Map[taskId, BuildTask]
  tasks: null

  constructor: ->
    @tasks = {}


  addTask: (taskParams) ->
    ###
    Registers and launches new task based on the given params
    @param Object taskParams
    @return Future[Nothing]
    ###
    TaskClass = @_chooseTask(taskParams)
    task = @tasks[taskParams.id] = new TaskClass(taskParams)
    task.run()
    task.ready().andThen =>
      delete @tasks[taskParams.id]


  _chooseTask: (taskParams) ->
    ###
    Selects task class by task params
    @return Class
    ###
    switch path.extname(taskParams.file)
      when '.coffee' then CompileCoffeeScript
      when '.js' then CopyFile
      else Fake


  getWorkload: ->
    ###
    Calculates and returns summary workload of all active tasks of this worker process
    @return Float
    ###
    _.reduce _.values(@tasks), ((memo, t) -> memo + t.getWorkload()), 0


  getFileInfo: (file) ->
    bundlesDir = 'public/bundles/'
    inBundles = file.substr(0, bundlesDir.length) == bundlesDir
    if inBundles
      relativePath = file.substr(bundlesDir.length)
      inWidgets = inBundles and file.indexOf('/widgets/') > 0
      inModels = inBundles and file.indexOf('/models/') > 0
      inTemplates = inBundles and file.indexOf('/templates/') > 0
      inBundle = inWidgets or inModels or inTemplates
      bundle = file.substr



worker = new BuildWorker

# manager process communication callback
process.on 'message', (task) ->
  worker.addTask(task).done ->
    process.send
      type: 'completed'
      task: task.id
      workload: worker.getWorkload()
  process.send
    type: 'accepted'
    task: task.id
    workload: worker.getWorkload()

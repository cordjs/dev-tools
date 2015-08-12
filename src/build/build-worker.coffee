###
Build worker process main script.
###
util = require 'util'

_ = require 'underscore'

CompileCoffeeScript   = require './task/CompileCoffeeScript'
CompileStylus         = require './task/CompileStylus'
CompileVdomWidget     = require './task/CompileVdomWidget'
CompileWidgetTemplate = require './task/CompileWidgetTemplate'
Fake                  = require './task/Fake'
CopyFile              = require './task/CopyFile'
RenderIndexHtml       = require './task/RenderIndexHtml'

requirejs = require 'requirejs'


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
    util.log(">>> #{taskParams.file}...")
    task.ready().finally =>
      delete @tasks[taskParams.id]


  _chooseTask: (taskParams) ->
    ###
    Selects task class by task params
    @return Class
    ###
    info = taskParams.info
    if info.isCoffee then CompileCoffeeScript
    else if info.isStylus then CompileStylus
    else if info.isVdom then CompileVdomWidget
    else if info.isWidgetTemplate then CompileWidgetTemplate
    else if info.isIndexPage then RenderIndexHtml
    else if info.ext == '.orig' or info.ext.substr(-1) == '~' then Fake
    else CopyFile


  failAllTasks: ->
    ###
    Used only in case of requireJs failure.
    While it cannot be caught in usual way we use onError handler and process message propagation
    ###
    err = new Error('Terminated due to requireJs error')
    for taskId of @tasks
      process.send
        type: 'failed'
        task: taskId
        error: err
    @tasks = []
    return


worker = new BuildWorker

# manager process communication callback
process.on 'message', (task) ->
  worker.addTask(task).done ->
    process.send
      type: 'completed'
      task: task.id
  .fail (err) ->
    if err.constructor.name != 'ExpectedError'
      console.error err.stack, err
    else
      err = err.underlyingError
    process.send
      type: 'failed'
      task: task.id
      error: err


requirejs.onError = (err) ->
  console.error 'ERROR while loading in REQUIREJS:', err, err.stack
  worker.failAllTasks()

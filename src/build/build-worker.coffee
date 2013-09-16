###
Build worker process main script.
###
_ = require('underscore')

CompileCoffeeScript = require('./task/CompileCoffeeScript')
CompileStylus = require('./task/CompileStylus')
CompileWidgetTemplate = require('./task/CompileWidgetTemplate')
Fake = require('./task/Fake')
CopyFile = require('./task/CopyFile')


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
    info = taskParams.info
    switch info.ext
      when '.coffee' then CompileCoffeeScript
      when '.styl' then CompileStylus
      when '.js' then CopyFile
      when '.html'
        if info.isWidgetTemplate
          CompileWidgetTemplate
        else
          Fake
      else Fake



worker = new BuildWorker

# manager process communication callback
process.on 'message', (task) ->
  worker.addTask(task).done ->
    process.send
      type: 'completed'
      task: task.id

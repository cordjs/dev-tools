// Generated by CoffeeScript 1.6.3
/*
Build worker process main script.
*/

var BuildWorker, CompileCoffeeScript, CompileStylus, CopyFile, Fake, path, worker, _;

path = require('path');

_ = require('underscore');

CompileCoffeeScript = require('./task/CompileCoffeeScript').CompileCoffeeScript;

CompileStylus = require('./task/CompileStylus').CompileStylus;

Fake = require('./task/Fake').Fake;

CopyFile = require('./task/CopyFile').CopyFile;

BuildWorker = (function() {
  BuildWorker.prototype.tasks = null;

  function BuildWorker() {
    this.tasks = {};
  }

  BuildWorker.prototype.addTask = function(taskParams) {
    /*
    Registers and launches new task based on the given params
    @param Object taskParams
    @return Future[Nothing]
    */

    var TaskClass, task,
      _this = this;
    TaskClass = this._chooseTask(taskParams);
    task = this.tasks[taskParams.id] = new TaskClass(taskParams);
    task.run();
    return task.ready().andThen(function() {
      return delete _this.tasks[taskParams.id];
    });
  };

  BuildWorker.prototype._chooseTask = function(taskParams) {
    /*
    Selects task class by task params
    @return Class
    */

    switch (path.extname(taskParams.file)) {
      case '.coffee':
        return CompileCoffeeScript;
      case '.styl':
        return CompileStylus;
      case '.js':
        return CopyFile;
      default:
        return Fake;
    }
  };

  BuildWorker.prototype.getWorkload = function() {
    /*
    Calculates and returns summary workload of all active tasks of this worker process
    @return Float
    */

    return _.reduce(_.values(this.tasks), (function(memo, t) {
      return memo + t.getWorkload();
    }), 0);
  };

  BuildWorker.prototype.getFileInfo = function(file) {
    var bundle, bundlesDir, inBundle, inBundles, inModels, inTemplates, inWidgets, relativePath;
    bundlesDir = 'public/bundles/';
    inBundles = file.substr(0, bundlesDir.length) === bundlesDir;
    if (inBundles) {
      relativePath = file.substr(bundlesDir.length);
      inWidgets = inBundles && file.indexOf('/widgets/') > 0;
      inModels = inBundles && file.indexOf('/models/') > 0;
      inTemplates = inBundles && file.indexOf('/templates/') > 0;
      inBundle = inWidgets || inModels || inTemplates;
      return bundle = file.substr;
    }
  };

  return BuildWorker;

})();

worker = new BuildWorker;

process.on('message', function(task) {
  worker.addTask(task).done(function() {
    return process.send({
      type: 'completed',
      task: task.id,
      workload: worker.getWorkload()
    });
  });
  return process.send({
    type: 'accepted',
    task: task.id,
    workload: worker.getWorkload()
  });
});
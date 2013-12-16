program = require 'commander'
packageInfo = require '../package.json'

# default values
DEFAULT_OUTPUT_DIR = 'target'
DEFAULT_CONFIG_NAME = 'default'
DEFAULT_SERVER_PORT = 18180

# getting version from the npm package definition
program
  .version(packageInfo.version,  '-V, --version')
  .on '--help', ->
    console.log "  CordJS version: #{packageInfo.version}"
    console.log ""

# common options
program
  .option('--chdir <path>', 'change the working directory')


program.withBuildOptions = (commandName) ->
  ###
  DRY for commands assuming build running
  ###
  @command(commandName)
    .option('-o, --out <dir>', 'output (target) directory relative to project root. defaults to "' +
                                  DEFAULT_OUTPUT_DIR + '"', DEFAULT_OUTPUT_DIR)
    .option('-d, --debug', 'development mode - copy all files to the outputDir')
    .option('-C, --clean', 'clean (remove) existing built files before starting new build')

exports.run = (actionCallbacks) ->
  ###
  Defines CLI commands and attaches injected action callbacks to them.
  Then parses CLI arguments and runs corresponding command callback.
  @param Object actionCallbacks map with callback-function for every command
  ###
  program
    .withBuildOptions('build')
    .description('build project')
    .option('-w, --watch', 'watch for changes in source files and rebuild them continuously')
    .action(actionCallbacks.build)

  program
    .withBuildOptions('run')
    .description('build project and run cordjs server')
    .option('-w, --watch', 'watch for changes in source files, rebuild and restart server continuously')
    .option('-c, --config <name>', 'configuration file name. defaults to "' + DEFAULT_CONFIG_NAME + '"', DEFAULT_CONFIG_NAME)
    .option('-p, --port <port>',   "server listening port. defaults to #{ DEFAULT_SERVER_PORT }", DEFAULT_SERVER_PORT)
    .action(actionCallbacks.run)

  program
    .command('clean')
    .description('clean (remove) build target directory')
    .option('-o, --out <dir>', 'output (target) directory relative to project root. defaults to "' +
                                  DEFAULT_OUTPUT_DIR + '"', DEFAULT_OUTPUT_DIR)
    .action(actionCallbacks.clean)

  program
    .command('optimize')
    .description('optimize the build (group, merge, minify etc...))')
    .option('-o, --out <dir>', 'output (target) directory relative to project root. defaults to "' +
                               DEFAULT_OUTPUT_DIR + '"', DEFAULT_OUTPUT_DIR)
    .option('-C, --clean', 'clean existing optimized files before writing new ones')
    .option('--disable-css', 'do not perform CSS group optimization. By default CSS optimization is enabled.')
    .option('--disable-js-minify', 'do not minify (via uglify-js) optimized javascript files. By default JS minification is enabled.')
    .action(actionCallbacks.optimize)

  program.parse(process.argv)

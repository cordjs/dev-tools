path = require('path')


preparePath = (filePath) ->
  filePath.split(path.sep).join('/')


module.exports = preparePath
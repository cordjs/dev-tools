should = require 'should'
CompileTest = require '../task/CompileTest'

describe 'Test compiler check', ->
  compileTest = new CompileTest
  definePathString = 'definePath(__filename, __dirname)'

  it 'Checks simple case, which consists of it with describe message without done argument', ->
    coffeeScript = """
describe 'One test, one touch', ->
  it 'should test something', ->
    nextCall()
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
#{definePathString}
describe 'One test, one touch', ->
  it 'should test something', ->
    #{definePathString}
    nextCall()
"""


  it 'Checks case, which consists of it with describe message with done argument', ->
    coffeeScript = """
describe 'One test, one touch', ->
  it 'should test something and executes callback', (done) ->
    nextCall()
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
#{definePathString}
describe 'One test, one touch', ->
  it 'should test something and executes callback', (done) ->
    #{definePathString}
    nextCall()
"""


  it 'Checks test-suite with multiple it-blocks', ->
    coffeeScript = """
describe 'Two tests, two touches', ->
  it 'should test first case', (done) ->
    firstCall()


  it 'should test second case', ->
    secondCall()
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
#{definePathString}
describe 'Two tests, two touches', ->
  it 'should test first case', (done) ->
    #{definePathString}
    firstCall()


  it 'should test second case', ->
    #{definePathString}
    secondCall()
"""
    
    
  it 'should test script with random it-letters in it', ->
    coffeeScript = """
describe 'It is simple test with it ', ->
  it 'should call it or not call it', ->
    itCallback(' it argument ->')
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
definePath(__filename, __dirname)
describe 'It is simple test with it ', ->
  it 'should call it or not call it', ->
    definePath(__filename, __dirname)
    itCallback(' it argument ->')
"""
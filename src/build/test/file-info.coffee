should = require('should')
fileInfo = require('../FileInfo')


describe 'FileInfo', ->
  fileInfo.setDirs('/User/user/project', '/User/user/project/target')
  fileInfo.setBundles [
    'cord/example'
    'example/ns/bundle'
    'ns2/ns3/b1'
    'test/bundle'
    'test/bundle2'
  ]

  it 'should setup base and target dirs correctly', ->
    should.equal(fileInfo.baseDir, '/User/user/project')
    fileInfo.targetDir.should.equal('/User/user/project/target')

  describe 'setBundles()', ->
    it 'should form correct bundle tree', ->
      should.exists(fileInfo.bundleTree.cord.example)
      should.not.exists(fileInfo.bundleTree.ns3)
      fileInfo.bundleTree.cord.example.should.equal(true)
      fileInfo.bundleTree.ns2.should.have.property('ns3')
      fileInfo.bundleTree.ns2.ns3.should.be.a('object')
      fileInfo.bundleTree.ns2.ns3.should.have.property('b1').with.a('boolean')

  describe 'getFileInfo', ->
    it 'should correctly detect widget templates', ->
      info = fileInfo.getFileInfo('public/bundles/test/bundle/widgets/testWidget/testWidget.html', 'test/bundle')
      info.isWidgetTemplate.should.be.true

  describe 'detectBundle()', ->
    it 'should return bundle part of correct path', ->
      fileInfo.detectBundle('public/bundles/test/bundle/widgets/testWidget/testWidget.html').should.equal('test/bundle')

    it 'should return empty string for incorrect path', ->
      fileInfo.detectBundle('public/test/bundle/widgets/testWidget/testWidget.html').should.equal('')

    it 'should correctly detect several bundles under common namespace', ->
      fileInfo.detectBundle('public/bundles/test/bundle/widgets/testWidget/testWidget.html').should.equal('test/bundle')
      fileInfo.detectBundle('public/bundles/test/bundle2/widgets/testWidget/testWidget.html').should.equal('test/bundle2')

  describe 'getTargetForSource() should work correctly for', ->
    it 'widget class', ->
      should.equal(
        fileInfo.getTargetForSource('/User/user/project/public/bundles/test/bundle/widgets/testWidget/TestWidget.coffee'),
        '/User/user/project/target/public/bundles/test/bundle/widgets/testWidget/TestWidget.js'
      )

    it 'widget template', ->
      should.equal(
        fileInfo.getTargetForSource('/User/user/project/public/bundles/test/bundle/widgets/testWidget/testWidget.html'),
        '/User/user/project/target/public/bundles/test/bundle/widgets/testWidget/testWidget.html.js'
      )

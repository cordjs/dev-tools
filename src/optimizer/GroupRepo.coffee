
class OptimizerGroup
  ###
  Simply little abstraction of module optimization group
  ###

  _items: null
  _modules: null
  _subGroups: null


  constructor: (@repo, @id, items) ->
    ###
    @param OptimizerGroupRepo repo group repository (creator)
    @param String id group unique id
    @param Array[String] items list of modules and/or sub-group ids which belongs to this new group
    ###
    @_items = items
    @_modules = []
    @_subGroups = []
    for item in items
      if group = repo.getGroup(item)
        @_subGroups.push(group)
        @_modules = @_modules.concat(group.getModules())
      else
        @_modules.push(item)


  getItems: -> @_items


  getModules: -> @_modules


  getSubGroups: -> @_subGroups



class GroupRepo
  ###
  Global repository of optimization groups.
  Creates groups and contains key-value list of OptimizationGroup by their IDs.
  ###

  _groups: null

  constructor: ->
    @_groups = {}


  createGroup: (groupId, modules) ->
    @_groups[groupId] = new OptimizerGroup(this, groupId, modules)


  getGroup: (groupId) -> @_groups[groupId]


  removeGroupDeep: (groupId) ->
    ###
    Removes the group with the given group id and all it's sub-groups from this group repository.
    Used to determine remaining unused groups.
    @param String groupId
    ###
    if @_groups[groupId]
      @removeGroupDeep(subGroup.id) for subGroup in @_groups[groupId].getSubGroups()
      delete @_groups[groupId]


  getGroups: -> @_groups



module.exports = GroupRepo

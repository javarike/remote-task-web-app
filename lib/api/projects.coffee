"use strict"

_ = require("underscore")

tag_project = (project, tags, cb=null) ->
  db = require("../module").db()
  db.models.tag.find (err, allTags) ->
    project.addTags _.filter(allTags, (t) -> t.tag in tags), (err) ->
      cb(err) if cb?

decorate_project = (project) ->
  project = JSON.parse(JSON.stringify(project))
  delete project.creator.password
  delete user.password for user in project.users
  project.tags = _.map project.tags, (tag) -> tag.tag
  project

add = (req, res, next) ->
  name = req.param("name") or "Project created at #{new Date}"
  priority = req.user.priority
  tags = _.union(["system:job:acceptable"], req.param("tags") or [], req.user.tags)
  req.db.models.project.create {name: name, priority: priority, creator_id: req.user.id}, (err, project) ->
    return next(err) if err?
    tag_project project, tags, (err) ->
      return next(err) if err?
      project.addUsers req.user, {owner: true}, (err) ->
        req.project = project
        next(err)

retrieve_project = (req, res, next) ->
  req.db.models.project.get req.project.id, (err, project) ->
    res.json decorate_project(project)

exports = module.exports =
  param: (req, res, next) ->
    project_id = req.param("project") or req.get("x-project")
    if project_id?
      req.user.getProjects (err, projects) ->
        return next(err) if err?
        req.project = _.find(projects, (proj) ->
          proj.id is Number(project_id)
        )
        if req.project?
          next()
        else
          res.json 403, error: "No permission to access the project."
    else
      next()

  add: [add, retrieve_project]

  list: (req, res, next) ->
    req.user.getProjects (err, projects) ->
      return next(err) if err?
      res.json _.map projects, (project) ->
        decorate_project project

  get: (req, res, next) ->
    res.json decorate_project(req.project)

  add_user: [
    (req, res, next) ->
      if req.user.id isnt req.project.creator_id
        return res.json 403, error: "Only creator has permission to add user."
      email = req.param("email")
      if not email
        return res.json 400, error: "no email parameter."
      req.db.models.user.find {email: email}, (err, users) ->
        return next(err) if err?
        return res.json 404, error: "Specified email doesn't exists." if users.length is 0
        if _.any(req.project.users, (user) -> user.id is users[0].id)
          res.send decorate_project(req.project)
        else
          req.project.addUsers users[0], (err) ->
            next err
    retrieve_project
  ]

  rm_user: [
    (req, res, next) ->
      if req.user.id isnt req.project.creator_id
        return res.json 403, error: "Only creator has permission to remove user."
      email = req.param("email")
      if not email
        return res.json 400, error: "no email parameter."
      if email is req.user.email
        return res.json 400, error: "can not remove yourself."
      req.db.models.user.find {email: email}, (err, users) ->
        return next(err) if err?
        return res.json 404, error: "Specified email doesn't exists." if users.length is 0
        req.project.removeUsers users, (err) ->
          next err
    retrieve_project
  ]

  get_device: (req, res) ->
    if req.methods.match {device_owner: req.project.creator.email, tags: req.project.tagList()}, req.device
      res.json req.device.toJSON()
    else
      res.json 403, error: "No permission to access the device."

  list_devices: (req, res) ->
    res.json req.data.models.devices.filter (device) ->
      req.methods.match {device_owner: req.project.creator.email, tags: req.project.tagList()}, device

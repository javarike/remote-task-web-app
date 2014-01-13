"use strict"

logger = require "../logger"

exports = module.exports = (zk_url, path, db_models, redis, subscriber, cb) ->
  require("./zk_node") zk_url, path, (zk) ->
    db_collection = require("./db_collection")(db_models)
    device_tags = new db_collection.DeviceTags
    device_tags.fetch()
    live_jobs = new db_collection.LiveJobs
    live_jobs.fetch()

    updateDeviceTag = (event) ->
      zk.models.devices.forEach (device) ->
        device.set("tags", device_tags.get(device.id)?.get("tags") or []) 

    zk.models.devices.on 'add', updateDeviceTag
    device_tags.on "change add remove", updateDeviceTag

    subscriber.subscribe c for c in ["db.device.tag", "db.task", "db.job"]
    subscriber.on "message", (channel, message) ->
      logger.info "Received pub-message: #{channel} - #{message}"
      switch channel
        when "db.device.tag" then device_tags.fetch()
        when "db.task", "db.job"
          live_jobs.fetch()

    cb(
      "zk_client": zk.client # zk client
      "models":
        "workstations": zk.models.workstations # workstation collection in zk
        "jobs": zk.models.jobs # jobs collection in zk
        "devices": zk.models.devices # devices collection in zk
        "live_jobs": live_jobs # new/running jobs in db
    )

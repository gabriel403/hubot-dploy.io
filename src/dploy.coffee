# Description:
#   Allows hubot to interact with dploy.io
#
# Commands:
#   hubot where can i deploy <app_name> - Displays the available environments for an application
#   hubot what apps can i deploy - Displays the available applications
#   hubot add <app_name> - Adds an app to the robot's brain
#   hubot add <env_name> to <app_name> - Adds an environment to an app
#   hubot set hook on <env_name> in <app_name> to <hook_url> - Sets the dploy hook for a givern env on an app
#   hubot deploy <app_name> to <env_name> - Deploy the specified app to the specified environment
#   hubot del <app_name> - Deletes an app
#   hubot del <env_name> from <app_name> - Deletes an environment from an app
#   hubot clear all - Deletes all apps
#
# Author:
#   gabriel403
#
module.exports = (robot) ->
  deploy_prefix = process.env['HUBOT_DPLOY_PREFIX'] || "deploy"
  deploy_rooms = (process.env['HUBOT_DPLOY_ROOMS'] || "deployments").split ','

  ###########################################################################
  # where can i deploy <app_name>
  #
  # Displays the available environments for an application
  robot.respond ///where\s+can\s+i\s+#{deploy_prefix}\s+([-_\.0-9a-z]+)///i, (msg) ->
    return if not isValidMsg(msg)

    app_name = msg.match[1]

    try
      app = validateApp(app_name)

      if !app
        msg.reply "#{app_name}? Never heard of it."
        return

      if Object.keys(app.environments).length is 0
        msg.reply "No environments for #{app_name}."
        return

      msg.reply Object.keys(app.environments).join(', ')
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # what apps can i deploy
  #
  # Displays the available applications
  robot.respond ///what\s+apps\s+can\s+i\s+#{deploy_prefix}///i, (msg) ->
    return if not isValidMsg(msg)

    try
      apps = retrieveApps()

      msg.reply Object.keys(apps).join(', ')
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err


  ###########################################################################
  # add <app_name>
  #
  # Adds an app to the robot's brain
  robot.respond /add\s+([-_\.0-9a-z]+)$/i, (msg) ->
    return if not isValidMsg(msg)

    app_name = msg.match[1]

    try
      app = validateApp(app_name)

      if app
        msg.reply "#{app_name} is already added."
        return

      saveApp({name: app_name, environments:{}})

      msg.reply "app #{app_name} added successfully, now add environments and dploy webhooks"
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # add <env_name> to <app_name>
  #
  # Adds an environment to an app
  robot.respond /add\s+([-_\.0-9a-z]+)\s+to\s+([-_\.0-9a-z]+)$/i, (msg) ->
    return if not isValidMsg(msg)

    env_name = msg.match[1]
    app_name = msg.match[2]

    try
      app = validateApp(app_name)
      if !app
        msg.reply "#{app_name}? Never heard of it."

      env = validateEnv(app, env_name)
      if env
        msg.reply "#{env_name} is already added to #{app_name}."
        return

      app.environments[env_name] = {name: env_name, hook: false}

      saveApp(app)

      msg.reply "env #{env_name} added to #{app_name} successfully, now add a dploy webhook!"
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # set hook on <env_name> in <app_name> to <hook_url>
  #
  # Sets the dploy hook for a givern env on an ap
  robot.respond /set\s+hook\s+on\s+([-_\.0-9a-z]+)\s+in\s+([-_\.0-9a-z]+)\s+to\s+(\S+)$/i, (msg) ->
    return if not isValidMsg(msg)

    env_name = msg.match[1]
    app_name = msg.match[2]
    hook = msg.match[3]

    try
      app = validateApp(app_name)
      if !app
        msg.reply "#{app_name}? Never heard of it."

      env = validateEnv(app, env_name)
      if !env
        msg.reply "#{env_name} is not in #{app_name}."
        return

      env.hook = hook

      saveApp(app)

      msg.reply "hook added to #{env_name} in #{app_name} successfully, now dploy!"
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # deploy <app_name> to <env_name>
  #
  # Deploy the specified app to the specified environment
  robot.respond ///#{deploy_prefix}\s+([-_\.0-9a-z]+)\s+to\s+([-_\.0-9a-z]+)$///i, (msg) ->
    return if not isValidMsg(msg)

    app_name = msg.match[1]
    env_name = msg.match[2]

    try
      app = validateApp(app_name)
      if !app
        msg.reply "#{app_name}? Never heard of it."

      env = validateEnv(app, env_name)
      if !env
        msg.reply "#{env_name} is not in #{app_name}."
        return

      if !'hook' of env or !env.hook
        msg.reply "#{env_name} has no webhook."
        return

      robot.brain.set 'dployLastRoom', msg.message.user.room

      # post to hook
      # robot.http("#{env.hook}&deployed_by=#{msg.message.user.email_address}&deploy_from_scratch=true")
      robot.http("#{env.hook}&deployed_by=#{msg.message.user.email_address}")
        .post() (err, res, body) ->
          body = JSON.parse(body)
          # pretend there's error checking code here
          if res.statusCode isnt 200
            msg.reply "There was an error calling the hook, that sucks."
            console.log err
            res.send 'error'
            return

          robot.logger.info body
          if body.release.revision is body.release.environment_revision and not body.release.deploy_from_scratch
            msg.reply "*#{app_name}* on *#{env_name}* is already at the latest revision."
          else
            msg.reply "*#{app_name}* on *#{env_name}* #{deploy_prefix} triggered."

          return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # del <app_name>
  #
  # Deletes an app
  robot.respond /del\s+([-_\.0-9a-z]+)$/i, (msg) ->
    return if not isValidMsg(msg)

    app_name = msg.match[1]

    try
      app = validateApp(app_name)

      if !app
        msg.reply "#{app_name}? Never heard of it."
        return

      delApp(app)

      msg.reply "app #{app_name} deleted successfully"
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # del <env_name> from <app_name>
  #
  # Deletes an environment from an app
  robot.respond /del\s+([-_\.0-9a-z]+)\s+from\s+([-_\.0-9a-z]+)$/i, (msg) ->
    return if not isValidMsg(msg)

    env_name = msg.match[1]
    app_name = msg.match[2]

    try
      app = validateApp(app_name)

      if !app
        msg.reply "#{app_name}? Never heard of it."
        return

      env = validateEnv(app, env_name)
      if !env
        msg.reply "#{env_name} is not in #{app_name}."
        return

      delEnv(app, env)

      msg.reply "env #{env_name} deleted from #{app_name} successfully"
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # clear all
  #
  # Deletes all apps
  robot.respond /clear all$/i, (msg) ->
    return if not isValidMsg(msg)

    try
      robot.brain.set 'dployApps', {}
      msg.reply "All apps cleared"
      return
    catch err
      msg.reply "There was an error, that sucks."
      console.log err

  ###########################################################################
  # listen for communication hooks from dploy
  #
  robot.router.post '/hubot/dploy', (req, res) ->
    res.send 'OK'

    requestType = req.get('Content-Type')
    body        = req.body
    robot.logger.info body
    body        = JSON.parse(Object.keys(body)[0]) if requestType is 'application/x-www-form-urlencoded'

    if body.comment is "WebHook Test"
      robot.messageRoom retrieveDployLastRoom(), "Repo #{body.repository} on #{body.environment} webhooks added."
      return

    if !!body.deployed_at
      robot.messageRoom retrieveDployLastRoom(), "Deployment of *#{body.repository}* to *#{body.environment}* finished successfully."
    else
      robot.messageRoom retrieveDployLastRoom(), "Deployment of *#{body.repository}* to *#{body.environment}* started."

    return

  isValidMsg = (msg) ->
    if msg.message.user.room in deploy_rooms
      return true

    msg.reply "Cannot deploy from this room."
    return false

  retrieveDployLastRoom = ->
    robot.brain.get('dployLastRoom') || deploy_rooms[0]

  retrieveApps = ->
    apps = robot.brain.get('dployApps')
    apps = {} if !apps
    apps

  validateApp = (name) ->
    apps = retrieveApps()

    if !apps or !name of apps
      false

    apps[name]

  validateEnv = (app, env_name) ->
    if !env_name of app.environments
      false

    app.environments[env_name]

  saveApp = (app) ->
    apps = retrieveApps()
    apps[app.name] = app

    console.log apps
    robot.brain.set 'dployApps', apps

  delApp = (app) ->
    apps = retrieveApps()
    delete apps[app.name]

    console.log apps
    robot.brain.set 'dployApps', apps

  delEnv = (app, env) ->
    apps = retrieveApps()
    delete apps[app.name].environments[env.name]

    console.log apps
    robot.brain.set 'dployApps', apps


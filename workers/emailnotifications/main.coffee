
{argv}    = require 'optimist'
{CronJob} = require 'cron'
Bongo     = require 'bongo'
Broker    = require 'broker'
{Base}    = Bongo
Emailer   = require '../social/lib/social/emailer'

{mq, mongo, email, uri} = require('koding-config-manager').load("main.#{argv.c}")

broker = new Broker mq

worker = new Bongo {
  mongo
  mq     : broker
  root   : __dirname
  models : '../social/lib/social/models'
}

log = ->
  console.log "[E-MAIL]", arguments...

log "E-Mail Notification Worker has started with PID #{process.pid}"

commonHeader     = (m)-> """[Koding Bot] A new notification"""
commonTemplate   = (m)->
  action  = ''
  preview = """
              <hr/>
                <p>
                  #{m.realContent?.body}
                </p>
              <hr/>
            """

  turnOffLink = "#{uri.address}/Unsubscribe/#{m.notification.unsubscribeId}"
  eventName   = flags[m.notification.eventFlag].definition

  switch m.event
    when 'FollowHappened'
      action = "is started to following you"
      m.contentLink = ''
      preview = ''
    when 'LikeIsAdded'
      action = "liked your"
    when 'PrivateMessageSent'
      action = "sent you a"
    when 'ReplyIsAdded'
      if m.receiver.getId().equals m.subjectContent.data.originId
        action = "commented on your"
      else
        action = "also commented on"
        # FIXME GG Implement the details
        # if m.realContent.origin?._id is m.sender._id
        #   action = "#{action} own"

  """
    <p>
      Hi #{m.receiver.profile.firstName},
    </p>

    <p><a href="#{uri.address}/#{m.sender.profile.nickname}">#{m.sender.profile.firstName} #{m.sender.profile.lastName}</a> #{action} #{m.contentLink}.</p>

    #{preview}

    You can turn off e-mail notifications for <a href="#{turnOffLink}">#{eventName}</a> or <a href="#{turnOffLink}/all">any kind of e-mails</a>.
    <br /> -- <br />
    Management
  """


flags =
  comment           :
    template        : commonTemplate
    definition      : "comments"
  likeActivities    :
    template        : commonTemplate
    definition      : "activity likes"
  followActions     :
    template        : commonTemplate
    definition      : "following states"
  privateMessage    :
    template        : commonTemplate
    definition      : "private messages"

prepareAndSendEmail = (notification)->

  sendEmail = (details)->
    {notification} = details
    # log "MAIL", flags[details.key].template details

    Emailer.send
      To        : details.email
      Subject   : commonHeader details
      HtmlBody  : flags[details.key].template details
    , (err, status)->
      log "An error occured: #{err}" if err
      notification.update $set: status: 'attempted', (err)->
        console.error err if err

  fetchSubjectContent = (contents, callback)->
    {constructorName} = contents.subject
    constructor       = Base.constructors[constructorName]
    constructor.one {_id:contents.subject.id}, (err, res)->
      if err then console.error err
      callback err, res

  fetchContent = (content, callback)->
    {constructorName} = content
    unless constructorName
      callback new KodingError 'Action type wrong.'
    else
      constructor     = Base.constructors[constructorName]
      {id}            = content
      constructor.one {_id:id}, (err, res)->
        if err then console.error err
        callback err, res

  fetchSubjectContentLink = (content, type, callback)->

    contentTypeLinkMap = (link)->
      pre = "<a href='#{uri.address}/Activity/#{link}'>"

      JReview           : "#{pre}review</a>"
      JComment          : "#{pre}comment</a>"
      JOpinion          : "#{pre}opinion</a>"
      JCodeSnip         : "#{pre}code snippet</a>"
      JTutorial         : "#{pre}tutorial</a>"
      JDiscussion       : "#{pre}discussion</a>"
      JLinkActivity     : "#{pre}link</a>"
      JStatusUpdate     : "#{pre}status update</a>"
      JPrivateMessage   : "#{pre}private message</a>"
      JQuestionActivity : "#{pre}question</a>"

    if type is 'JPrivateMessage'
      callback null, "<a href='https://koding.com/Inbox'>private message</a>"
    else if content.slug
      callback null, contentTypeLinkMap(content.slug)[type]
    else
      {constructorName} = content.bongo_
      constructor = Base.constructors[constructorName]
      constructor.fetchRelated? content._id, (err, relatedContent)->
        if err then callback err
        else
          if relatedContent.slug? or constructorName in ['JReview']
            callback null, contentTypeLinkMap(relatedContent.slug)[type]
          else
            constructor = \
              Base.constructors[relatedContent.bongo_.constructorName]
            constructor.fetchRelated? relatedContent._id, (err, content)->
              if err then callback err
              else
                callback null, contentTypeLinkMap(content.slug)[type]

  {JAccount, JEmailNotificationGG} = worker.models

  {event}     = notification.data
  if event is 'FollowHappened'
    contentType = 'JAccount'
  else
    contentType = notification.activity.subject.constructorName

  # Fetch Receiver
  JAccount.one {_id:notification.receiver.id}, (err, receiver)->
    if err then callback err
    else
      # Fetch Receiver E-Mail choices
      JEmailNotificationGG.checkEmailChoice
        event       : event
        contentType : contentType
        username    : receiver.profile.nickname
      , (err, state, key, email)->
        if err
          console.error "Could not load user record"
          callback err
        else
          if state isnt 'on'
            log 'User disabled e-mails, ignored for now.'
            notification.update $set: status: 'postponed', (err)->
              console.error err if err
          else
            # log "Trying to send it... to...", email
            # Fetch Sender
            JAccount.one {_id:notification.sender}, (err, sender)->
              if err then callback err
              else
                details = {sender, receiver, event, email, key, notification}
                if event is 'FollowHappened'
                  sendEmail details
                else
                  # Fetch Subject Content
                  fetchSubjectContent notification.activity, \
                  (err, subjectContent)->
                    if err then callback err
                    else
                      realContent = subjectContent
                      # Create object which we pass to template later
                      details.subjectContent = subjectContent
                      details.realContent    = realContent
                      # Fetch Subject Content-Link
                      # If Subject is a secondary level content like JComment
                      # we need to get its parent's slug to show link correctly
                      fetchSubjectContentLink subjectContent, contentType, \
                      (err, link)->
                        if err then callback err
                        else
                          details.contentLink = link
                          if event is 'ReplyIsAdded'
                            # Fetch RealContent
                            fetchContent notification.activity.content, \
                            (err, content)->
                              if err then callback err
                              else
                                details.realContent = content
                                sendEmail details
                          else
                            sendEmail details

job = new CronJob email.notificationCron, ->

  {JEmailNotificationGG} = worker.models
  # log "Checking for waiting queue..."

  JEmailNotificationGG.some {status: "queued"}, {limit:100}, (err, emails)->
    if err
      log "Could not load email queue!"
    else
      if emails.length > 0
        log "There are #{emails.length} mail in queue."
        for email in emails
          prepareAndSendEmail email
      # else
      #   log "E-Mail queue is empty. Yay."

job.start()
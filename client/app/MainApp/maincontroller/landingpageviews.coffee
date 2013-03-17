
class LandingPageSideBar extends KDView

  constructor:(isLoggedIn = no)->

    options     =
      lazyDomId : 'landing-page-sidebar'

    super options

    @navController = new LandingPageNavigationController
      view         : new NavigationList
        itemClass  : LandingPageNavigationLink
        type       : "navigation"
      scrollView   : no
      wrapper      : no
    ,
      items : [
        { title : "Register", action : "register", loggedOut : yes }
        { type  : "separator" }
        { title : "Logout",   action : "logout",   loggedIn  : yes }
        { title : "Login",    action : "login",    loggedOut : yes }
      ]

    @addSubView @nav = @navController.getView()

class LandingPageNavigationController extends NavigationController

  constructor: ->
    super

    @lc = @getSingleton 'lazyDomController'

  instantiateListItems:(items)->

    # Build groups menu
    if @lc.userEnteredFromGroup()

      {groupEntryPoint} = KD.config

      if KD.isLoggedIn()
        KD.whoami().fetchGroupRoles groupEntryPoint, (err, roles)=>
          if err then console.warn err
          else if roles.length
            items.unshift \
              { title: 'Open Group', path: "/#{groupEntryPoint}/Activity"}
            @_instantiateListItems items
          else
            KD.remote.api.JMembershipPolicy.byGroupSlug groupEntryPoint,
              (err, policy)=>
                if err then console.warn err
                else if policy?.approvalEnabled
                  items.unshift \
                    { title: 'Request to Join', action: 'request'}
                else
                  items.unshift \
                    { title: 'Join Group', action: 'join-group'}
                @_instantiateListItems items

      else
        items.unshift { title: 'Request to Join', action: 'request'}
        @_instantiateListItems items

    else if @lc.userEnteredFromProfile()

      log 'entered from profile!'
      profileItems = [
        { title : 'My Activities',action : 'activity', type : 'selected'}
        { title : 'My Topics', action : 'topics', type : 'main' }
        { title : 'My People', action : 'members', type : 'main'}
        { title : 'My Groups', action : 'groups', type : 'main'}
        { title : 'My Apps', action : 'apps', type : 'main'}
      ]
      items = profileItems.concat items
      @_instantiateListItems items
    else
      @_instantiateListItems items

  _instantiateListItems:(items)->
    newItems = for itemData in items
      if KD.isLoggedIn()
        continue if itemData.loggedOut
      else
        continue if itemData.loggedIn
      @getListView().addItem itemData

class LandingPageNavigationLink extends NavigationLink

  constructor:(options = {}, data)->
    data.type or= "account"
    super options, data

  openPath:(path)->
    @getSingleton('router').handleRoute path
    @getSingleton('lazyDomController').hideLandingPage()

  click:(event)->
    {action, appPath, title, path, type} = @getData()
    log "here", @getData()

    mc = @getSingleton 'mainController'
    {loginScreen} = mc

    if path
      @openPath path
      return

    switch action
      when 'login'
        loginScreen.animateToForm 'login'
      when 'register'
        loginScreen.animateToForm 'register'
      when 'request'
        loginScreen.animateToForm 'lr'
      when 'join-group'
        {groupEntryPoint} = KD.config
        KD.remote.api.JGroup.one slug: groupEntryPoint, (err, group)=>
          error err if err
          if err then new KDNotificationView
            title : "An error occured, please try again"
          else unless group?
            new KDNotificationView title : "No such group!"
          else group.join (err, response)=>
            error err if err
            if err
              new KDNotificationView
                title : "An error occured, please try again"
            else
              new KDNotificationView
                title : "You successfully joined to group!"
              @openPath "/#{groupEntryPoint}/Activity"

      when 'logout'
        $('#kdmaincontainer').addClass 'hidden'
        @openPath '/Logout'

      when 'activity'
        log 'Activity'
      when 'topics'
        log 'Topics'
      when 'members'
        log 'Members'
      when 'groups'
        log 'Groups'
      when 'apps'
        log 'Apps'


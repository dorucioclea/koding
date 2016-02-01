kd                    = require 'kd'
$                     = require 'jquery'
React                 = require 'kd-react'
ReactDOM              = require 'react-dom'
immutable             = require 'immutable'
ActivityFlux          = require 'activity/flux'
ChatPaneView          = require './view'
scrollToElement       = require 'app/util/scrollToElement'
getScrollablePosition = require 'app/util/getScrollablePosition'
KDReactorMixin        = require 'app/flux/base/reactormixin'

module.exports = class ChatPaneContainer extends React.Component

  @propsTypes =
    thread        : React.PropTypes.instanceOf immutable.Map
    onInviteClick : React.PropTypes.func
    showItemMenu  : React.PropTypes.bool
    onLoadMore    : React.PropTypes.func


  @defaultProps =
    thread        : immutable.Map()
    onInviteClick : kd.noop
    showItemMenu  : yes
    onLoadMore    : kd.noop


  getDataBindings: ->

    return {
      selectedMessageId: ActivityFlux.getters.selectedMessageThreadId
    }


  flag: (key) -> @props.thread?.getIn ['flags', key]
  channel: (key) -> @props.thread?.getIn ['channel', key]


  componentDidMount: ->

    { view } = @refs

    view.refs.content.show()
    scrollTop = @flag 'scrollPosition'
    view.scrollToPosition scrollTop  if scrollTop


  componentWillUnmount: ->

    { view } = @refs

    { scrollTop } = view.getScrollParams()
    { channel }   = ActivityFlux.actions

    view.refs.content.hide()

    kd.utils.defer =>
      channel.setLastSeenTime (@channel 'id'), Date.now()
      channel.setScrollPosition (@channel 'id'), scrollTop


  componentDidUpdate: (prevProps, prevState) ->

    prevSelectedMessageId = prevState.selectedMessageId
    { selectedMessageId } = @state

    prevThread = prevProps.thread
    { thread } = @props

    return  unless prevThread and thread

    { view } = @refs

    hadEditingMessage = prevThread.getIn [ 'flags', 'hasEditingMessage' ]
    hasEditingMessage = @flag 'hasEditingMessage'

    if selectedMessageId and selectedMessageId isnt prevSelectedMessageId
      element = helper.getMessageElement selectedMessageId
      scrollToElement element, yes

    else if @flag 'hasSubmittingMessage'
      view.scrollToBottom()

    else if @isThresholdReached
      view.keepPosition()

    else if hasEditingMessage and not hadEditingMessage
      message = thread.get('messages').find (msg) -> msg.get '__isEditing'
      if message
        element = helper.getMessageElement message.get 'id'

        # this delay is needed for chat input to resize its textarea
        kd.utils.wait 50, -> scrollToElement element

    else
      hasStoppedMessageEditing = not hasEditingMessage and hadEditingMessage
      hasRemovedMessage        = thread.get('messages').size < prevThread.get('messages').size

      view.getScroller()._update()  if hasStoppedMessageEditing or hasRemovedMessage

    @updateDateMarkersPosition()
    @updateUnreadMessagesLabel()

    @isThresholdReached = no


  onScroll: ->

    @updateDateMarkersPosition()
    @updateUnreadMessagesLabel()


  updateDateMarkersPosition: ->

    { view }    = @refs
    { content } = view.refs

    content.refs.ChatList.updateDateMarkersPosition()


  onTopThresholdReached: (event) ->

    messages = @props.thread.get 'messages'

    return  if @isThresholdReached

    return  unless messages.size

    @isThresholdReached = yes

    kd.utils.wait 500, => @props.onLoadMore()


  onGlance: -> ActivityFlux.actions.channel.glance @channel 'id'


  updateUnreadMessagesLabel: ->

    unreadCount = @channel 'unreadCount'
    return  unless unreadCount

    messages = @props.thread.get('messages').toList()
    message  = messages.get messages.size - unreadCount
    return  unless message

    { view }    = @refs
    { content } = view.refs
    element     = helper.getMessageElement message.get 'id'
    label       = content.refs.unreadCountLabel
    position    = getScrollablePosition element

    label.setPosition position


  render: ->

    <ChatPaneView {...@props}
      ref                   = 'view'
      selectedMessageId     = { @state.selectedMessageId }
      onTopThresholdReached = { @bound 'onTopThresholdReached' }
      onGlance              = { @bound 'onGlance' }
      onScroll              = { @bound 'onScroll' }
      isMessagesLoading     = { @isThresholdReached }>
        {@props.children}
    </ChatPaneView>


  helper =

    getMessageElement: (messageId) ->

      return $("[data-message-id=#{messageId}]").get(0)


ChatPaneContainer.include [KDReactorMixin]

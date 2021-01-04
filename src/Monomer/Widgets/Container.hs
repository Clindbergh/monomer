{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Monomer.Widgets.Container (
  module Monomer.Core,
  module Monomer.Core.Combinators,
  module Monomer.Event,
  module Monomer.Graphics,
  module Monomer.Widgets.Util,

  Container(..),
  ContainerGetSizeReqHandler(..),
  ContainerResizeHandler(..),
  createContainer,
  initWrapper,
  mergeWrapper,
  handleEventWrapper,
  handleMessageWrapper,
  findByPointWrapper,
  findNextFocusWrapper,
  resizeWrapper,
  renderWrapper,
  renderContainer,
  defaultFindByPoint,
  defaultRender
) where

import Control.Lens ((&), (^.), (^?), (.~), (%~), _Just)
import Control.Monad
import Data.Default
import Data.Foldable (fold)
import Data.Maybe
import Data.Map.Strict (Map)
import Data.Typeable (Typeable)
import Data.Sequence (Seq(..), (<|), (|>), (><))

import qualified Data.Map.Strict as M
import qualified Data.Sequence as Seq

import Monomer.Core
import Monomer.Core.Combinators
import Monomer.Event
import Monomer.Graphics
import Monomer.Widgets.Util

import qualified Monomer.Lens as L

type ContainerGetBaseStyle s e
  = GetBaseStyle s e

type ContainerGetActiveStyle s e
  = WidgetEnv s e
  -> WidgetNode s e
  -> StyleState

type ContainerInitHandler s e
  = WidgetEnv s e
  -> WidgetNode s e
  -> WidgetResult s e

type ContainerMergeHandler s e
  = WidgetEnv s e
  -> Maybe WidgetState
  -> WidgetNode s e
  -> WidgetNode s e
  -> WidgetResult s e

type ContainerMergeChildrenRequiredHandler s e
  = WidgetEnv s e
  -> Maybe WidgetState
  -> WidgetNode s e
  -> WidgetNode s e
  -> Bool

type ContainerMergePostHandler s e
  = WidgetEnv s e
  -> WidgetResult s e
  -> Maybe WidgetState
  -> WidgetNode s e
  -> WidgetNode s e
  -> WidgetResult s e

type ContainerDisposeHandler s e
  = WidgetEnv s e
  -> WidgetNode s e
  -> WidgetResult s e

type ContainerGetStateHandler s e
  = WidgetEnv s e
  -> Maybe WidgetState

type ContainerFindNextFocusHandler s e
  = WidgetEnv s e
  -> FocusDirection
  -> Path
  -> WidgetNode s e
  -> Seq (WidgetNode s e)

type ContainerFindByPointHandler s e
  = WidgetEnv s e
  -> Path
  -> Point
  -> WidgetNode s e
  -> Maybe Int

type ContainerEventHandler s e
  = WidgetEnv s e
  -> Path
  -> SystemEvent
  -> WidgetNode s e
  -> Maybe (WidgetResult s e)

type ContainerMessageHandler s e
  = forall i . Typeable i
  => WidgetEnv s e
  -> Path
  -> i
  -> WidgetNode s e
  -> Maybe (WidgetResult s e)

type ContainerGetSizeReqHandler s e
  = WidgetEnv s e
  -> Maybe WidgetState
  -> WidgetNode s e
  -> Seq (WidgetNode s e)
  -> (SizeReq, SizeReq)

type ContainerResizeHandler s e
  = WidgetEnv s e
  -> Rect
  -> Rect
  -> Seq (WidgetNode s e)
  -> WidgetNode s e
  -> (WidgetNode s e, Seq (Rect, Rect))

type ContainerRenderHandler s e
  = Renderer
  -> WidgetEnv s e
  -> WidgetNode s e
  -> IO ()

data Container s e = Container {
  containerUseScissor :: Bool,
  containerResizeRequired :: Bool,
  containerIgnoreEmptyArea :: Bool,
  containerUseCustomSize :: Bool,
  containerUseChildrenSizes :: Bool,
  containerGetBaseStyle :: ContainerGetBaseStyle s e,
  containerGetActiveStyle :: ContainerGetActiveStyle s e,
  containerInit :: ContainerInitHandler s e,
  containerMerge :: ContainerMergeHandler s e,
  containerMergeChildrenRequired :: ContainerMergeChildrenRequiredHandler s e,
  containerMergePost :: ContainerMergePostHandler s e,
  containerDispose :: ContainerDisposeHandler s e,
  containerGetState :: ContainerGetStateHandler s e,
  containerFindNextFocus :: ContainerFindNextFocusHandler s e,
  containerFindByPoint :: ContainerFindByPointHandler s e,
  containerHandleEvent :: ContainerEventHandler s e,
  containerHandleMessage :: ContainerMessageHandler s e,
  containerGetSizeReq :: ContainerGetSizeReqHandler s e,
  containerResize :: ContainerResizeHandler s e,
  containerRender :: ContainerRenderHandler s e,
  containerRenderAfter :: ContainerRenderHandler s e
}

instance Default (Container s e) where
  def = Container {
    containerUseScissor = True,
    containerResizeRequired = True,
    containerIgnoreEmptyArea = False,
    containerUseCustomSize = False,
    containerUseChildrenSizes = False,
    containerGetBaseStyle = defaultGetBaseStyle,
    containerGetActiveStyle = defaultGetActiveStyle,
    containerInit = defaultInit,
    containerMerge = defaultMerge,
    containerMergeChildrenRequired = defaultMergeRequired,
    containerMergePost = defaultMergePost,
    containerDispose = defaultDispose,
    containerGetState = defaultGetState,
    containerFindNextFocus = defaultFindNextFocus,
    containerFindByPoint = defaultFindByPoint,
    containerHandleEvent = defaultHandleEvent,
    containerHandleMessage = defaultHandleMessage,
    containerGetSizeReq = defaultGetSizeReq,
    containerResize = defaultResize,
    containerRender = defaultRender,
    containerRenderAfter = defaultRender
  }

createContainer :: Container s e -> Widget s e
createContainer container = Widget {
  widgetInit = initWrapper container,
  widgetMerge = mergeWrapper container,
  widgetDispose = disposeWrapper container,
  widgetGetState = containerGetState container,
  widgetGetInstanceTree = getInstanceTree,
  widgetFindNextFocus = findNextFocusWrapper container,
  widgetFindByPoint = findByPointWrapper container,
  widgetHandleEvent = handleEventWrapper container,
  widgetHandleMessage = handleMessageWrapper container,
  widgetResize = resizeWrapper container,
  widgetRender = renderWrapper container
}

-- | Get base style for component
defaultGetBaseStyle :: ContainerGetBaseStyle s e
defaultGetBaseStyle wenv node = Nothing

defaultGetActiveStyle :: ContainerGetActiveStyle s e
defaultGetActiveStyle wenv node = activeStyle wenv node

-- | Init handler
defaultInit :: ContainerInitHandler s e
defaultInit wenv node = resultWidget node

initWrapper
  :: Container s e
  -> WidgetEnv s e
  -> WidgetNode s e
  -> WidgetResult s e
initWrapper container wenv node = result where
  initHandler = containerInit container
  getBaseStyle = containerGetBaseStyle container
  styledNode = initNodeStyle getBaseStyle wenv node
  WidgetResult tempNode reqs events = initHandler wenv styledNode
  children = tempNode ^. L.children
  initChild idx child = widgetInit newWidget wenv newChild where
    newChild = cascadeCtx wenv tempNode child idx
    newWidget = newChild ^. L.widget
  results = Seq.mapWithIndex initChild children
  newReqs = foldMap _wrRequests results
  newEvents = foldMap _wrEvents results
  newChildren = fmap _wrNode results
  newNode = updateSizeReq container wenv $ tempNode
    & L.children .~ newChildren
  result = WidgetResult newNode (reqs <> newReqs) (events <> newEvents)

-- | Merging
defaultMerge :: ContainerMergeHandler s e
defaultMerge wenv oldState oldNode newNode = resultWidget newNode

defaultMergeRequired :: ContainerMergeChildrenRequiredHandler s e
defaultMergeRequired wenv oldState oldNode newNode = True

defaultMergePost :: ContainerMergePostHandler s e
defaultMergePost wenv result oldState oldNode node = result

mergeWrapper
  :: Container s e
  -> WidgetEnv s e
  -> WidgetNode s e
  -> WidgetNode s e
  -> WidgetResult s e
mergeWrapper container wenv oldNode newNode = result where
  getBaseStyle = containerGetBaseStyle container
  mergeRequiredHandler = containerMergeChildrenRequired container
  mergeHandler = containerMerge container
  mergePostHandler = containerMergePost container

  mergeRequired = mergeRequiredHandler wenv oldState oldNode newNode
  oldFlags = [oldNode ^. L.info . L.visible, oldNode ^. L.info . L.enabled]
  newFlags = [newNode ^. L.info . L.visible, newNode ^. L.info . L.enabled]
  oldState = widgetGetState (oldNode ^. L.widget) wenv
  styledNode = initNodeStyle getBaseStyle wenv newNode
  pResult = mergeParent mergeHandler wenv oldState oldNode styledNode
  cResult = mergeChildren wenv oldNode newNode pResult
  vResult = mergeChildrenCheckVisible oldNode cResult
  tmpRes
    | mergeRequired || oldFlags /= newFlags = vResult
    | otherwise = pResult & L.node . L.children .~ oldNode ^. L.children
  postRes = mergePostHandler wenv tmpRes oldState oldNode (tmpRes ^. L.node)
  result
    | isResizeResult (Just postRes) = postRes
        & L.node .~ updateSizeReq container wenv (postRes ^. L.node)
    | otherwise = postRes

mergeParent
  :: ContainerMergeHandler s e
  -> WidgetEnv s e
  -> Maybe WidgetState
  -> WidgetNode s e
  -> WidgetNode s e
  -> WidgetResult s e
mergeParent mergeHandler wenv oldState oldNode newNode = result where
  oldInfo = oldNode ^. L.info
  tempNode = newNode
    & L.info . L.viewport .~ oldInfo ^. L.viewport
    & L.info . L.renderArea .~ oldInfo ^. L.renderArea
    & L.info . L.sizeReqW .~ oldInfo ^. L.sizeReqW
    & L.info . L.sizeReqH .~ oldInfo ^. L.sizeReqH
  result = mergeHandler wenv oldState oldNode tempNode

mergeChildren
  :: WidgetEnv s e
  -> WidgetNode s e
  -> WidgetNode s e
  -> WidgetResult s e
  -> WidgetResult s e
mergeChildren wenv oldNode newNode result = newResult where
  WidgetResult uNode uReqs uEvents = result
  oldChildren = oldNode ^. L.children
  oldCsIdx = Seq.mapWithIndex (,) oldChildren
  updatedChildren = uNode ^. L.children
  mergeChild idx child = (idx, cascadeCtx wenv uNode child idx)
  newCsIdx = Seq.mapWithIndex mergeChild updatedChildren
  localKeys = buildLocalMap oldChildren
  cResult = mergeChildrenSeq wenv localKeys newNode oldCsIdx newCsIdx
  (mergedResults, removedResults) = cResult
  mergedChildren = fmap _wrNode mergedResults
  concatSeq seqs = fold seqs
  mergedReqs = concatSeq $ fmap _wrRequests mergedResults
  mergedEvents = concatSeq $ fmap _wrEvents mergedResults
  removedReqs = concatSeq $ fmap _wrRequests removedResults
  removedEvents = concatSeq $ fmap _wrEvents removedResults
  mergedNode = uNode & L.children .~ mergedChildren
  newReqs = uReqs <> mergedReqs <> removedReqs
  newEvents = uEvents <> mergedEvents <> removedEvents
  newResult = WidgetResult mergedNode newReqs newEvents

mergeChildrenSeq
  :: WidgetEnv s e
  -> Map WidgetKey (WidgetNode s e)
  -> WidgetNode s e
  -> Seq (Int, WidgetNode s e)
  -> Seq (Int, WidgetNode s e)
  -> (Seq (WidgetResult s e), Seq (WidgetResult s e))
mergeChildrenSeq wenv localKeys newNode oldItems Empty = res where
  dispose (idx, child) = widgetDispose (child ^. L.widget) wenv child
  removed = fmap dispose oldItems
  res = (Empty, removed)
mergeChildrenSeq wenv localKeys newNode Empty newItems = res where
  init (idx, child) = widgetInit (child ^. L.widget) wenv child
  merged = fmap init newItems
  res = (merged, Empty)
mergeChildrenSeq wenv localKeys newNode oldItems newItems = res where
  (_, oldChild) :<| oldChildren = oldItems
  (newIdx, newChild) :<| newChildren = newItems
  globalKeys = wenv ^. L.globalKeys
  newWidget = newChild ^. L.widget
  newChildKey = newChild ^. L.info . L.key
  oldKeyMatch = newChildKey >>= \key -> findWidgetByKey key localKeys globalKeys
  oldMatch = fromJust oldKeyMatch
  mergedOld = widgetMerge newWidget wenv oldChild $ newChild
    & L.info . L.widgetId .~ oldChild ^. L.info . L.widgetId
  mergedKey = widgetMerge newWidget wenv oldMatch $ newChild
    & L.info . L.widgetId .~ oldMatch ^. L.info . L.widgetId
  initNew = widgetInit newWidget wenv newChild
    & L.requests %~ (|> ResizeWidgets)
  isMergeKey = isJust oldKeyMatch && instanceMatches newChild oldMatch
  (child, oldRest)
    | instanceMatches newChild oldChild = (mergedOld, oldChildren)
    | isMergeKey = (mergedKey, oldItems)
    | otherwise = (initNew, oldItems)
  (cmerged, cremoved)
    = mergeChildrenSeq wenv localKeys newNode oldRest newChildren
  merged = child <| cmerged
  res = (merged, cremoved)

mergeChildrenCheckVisible
  :: WidgetNode s e
  -> WidgetResult s e
  -> WidgetResult s e
mergeChildrenCheckVisible oldNode result = newResult where
  newNode = result ^. L.node
  resizeRequired = visibleChildrenChanged oldNode newNode
  newResult
    | resizeRequired = result & L.requests %~ (|> ResizeWidgets)
    | otherwise = result

-- | Dispose handler
defaultDispose :: ContainerInitHandler s e
defaultDispose wenv node = resultWidget node

disposeWrapper
  :: Container s e
  -> WidgetEnv s e
  -> WidgetNode s e
  -> WidgetResult s e
disposeWrapper container wenv node = result where
  disposeHandler = containerDispose container
  WidgetResult tempNode reqs events = disposeHandler wenv node
  children = tempNode ^. L.children
  dispose child = widgetDispose (child ^. L.widget) wenv child
  results = fmap dispose children
  newReqs = foldMap _wrRequests results
  newEvents = foldMap _wrEvents results
  result = WidgetResult node (reqs <> newReqs) (events <> newEvents)

-- | State Handling helpers
defaultGetState :: ContainerGetStateHandler s e
defaultGetState _ = Nothing

-- | Find next focusable item
defaultFindNextFocus :: ContainerFindNextFocusHandler s e
defaultFindNextFocus wenv direction start node = vchildren where
  vchildren = Seq.filter (^. L.info . L.visible) (node ^. L.children)

findNextFocusWrapper
  :: Container s e
  -> WidgetEnv s e
  -> FocusDirection
  -> Path
  -> WidgetNode s e
  -> Maybe Path
findNextFocusWrapper container wenv direction start node = nextFocus where
  handler = containerFindNextFocus container
  handlerResult = handler wenv direction start node
  children
    | direction == FocusBwd = Seq.reverse handlerResult
    | otherwise = handlerResult
  nextFocus
    | isFocusCandidate direction start node = Just path
    | otherwise = findFocusCandidate children wenv direction start
    where
      path = node ^. L.info . L.path

findFocusCandidate
  :: Seq (WidgetNode s e)
  -> WidgetEnv s e
  -> FocusDirection
  -> Path
  -> Maybe Path
findFocusCandidate Empty _ _ _ = Nothing
findFocusCandidate (ch :<| chs) wenv dir start = result where
  isWidgetAfterStart
    | dir == FocusBwd = isWidgetBeforePath start ch
    | otherwise = isWidgetParentOfPath start ch || isWidgetAfterPath start ch
  candidate = widgetFindNextFocus (ch ^. L.widget) wenv dir start ch
  result
    | isWidgetAfterStart && isJust candidate = candidate
    | otherwise = findFocusCandidate chs wenv dir start

-- | Find instance matching point
defaultFindByPoint :: ContainerFindByPointHandler s e
defaultFindByPoint wenv startPath point node = result where
  children = node ^. L.children
  pointInWidget wi = wi ^. L.visible && pointInRect point (wi ^. L.viewport)
  result = Seq.findIndexL (pointInWidget . _wnInfo) children

findByPointWrapper
  :: Container s e
  -> WidgetEnv s e
  -> Path
  -> Point
  -> WidgetNode s e
  -> Maybe Path
findByPointWrapper container wenv start point node = result where
  ignoreEmpty = containerIgnoreEmptyArea container
  handler = containerFindByPoint container
  isVisible = node ^. L.info . L.visible
  inVp = pointInViewport point node
  path = node ^. L.info . L.path
  children = node ^. L.children
  newStartPath = Seq.drop 1 start
  childIdx = case newStartPath of
    Empty -> handler wenv start point node
    p :<| ps -> Just p
  validateIdx p
    | Seq.length children > p = Just p
    | otherwise = Nothing
  resultPath = case childIdx >>= validateIdx of
    Just idx -> childPath where
      childPath = widgetFindByPoint childWidget wenv newStartPath point child
      child = Seq.index children idx
      childWidget = child ^. L.widget
    Nothing
      | not ignoreEmpty -> Just $ node ^. L.info . L.path
      | otherwise -> Nothing
  result
    | isVisible && (inVp || resultPath /= Just path) = resultPath
    | otherwise = Nothing

-- | Event Handling
defaultHandleEvent :: ContainerEventHandler s e
defaultHandleEvent wenv target evt node = Nothing

handleEventWrapper
  :: Container s e
  -> WidgetEnv s e
  -> Path
  -> SystemEvent
  -> WidgetNode s e
  -> Maybe (WidgetResult s e)
handleEventWrapper container wenv target evt node
  | not (node ^. L.info . L.visible) = Nothing
  | targetReached || not targetValid = pResultStyled
  | otherwise = cResultStyled
  where
    -- Having targetValid = False means the next path step is not in
    -- _wiChildren, but may still be valid in the receiving widget
    -- For example, Composite has its own tree of child widgets with (possibly)
    -- different types for Model and Events, and is candidate for the next step
    style = containerGetActiveStyle container wenv node
    pHandler = containerHandleEvent container
    targetReached = isTargetReached target node
    targetValid = isTargetValid target node
    childIdx = fromJust $ nextTargetStep target node
    children = node ^. L.children
    child = Seq.index children childIdx
    childWidget = child ^. L.widget
    -- Event targeted at parent
    pResponse = pHandler wenv target evt node
    pResultStyled = handleStyleChange wenv target style def node evt
      $ handleSizeReqChange container wenv node (Just evt) pResponse
    -- Event targeted at children
    childrenIgnored = isJust pResponse && ignoreChildren (fromJust pResponse)
    cResponse
      | childrenIgnored || not (child ^. L.info . L.enabled) = Nothing
      | otherwise = widgetHandleEvent childWidget wenv target evt child
    cResult = mergeParentChildEvts node pResponse cResponse childIdx
    cResultStyled = handleStyleChange wenv target style def node evt
      $ handleSizeReqChange container wenv node (Just evt) cResult

mergeParentChildEvts
  :: WidgetNode s e
  -> Maybe (WidgetResult s e)
  -> Maybe (WidgetResult s e)
  -> Int
  -> Maybe (WidgetResult s e)
mergeParentChildEvts _ Nothing Nothing _ = Nothing
mergeParentChildEvts _ pResponse Nothing _ = pResponse
mergeParentChildEvts original Nothing (Just cResponse) idx = Just $ cResponse {
    _wrNode = replaceChild original (_wrNode cResponse) idx
  }
mergeParentChildEvts original (Just pResponse) (Just cResponse) idx
  | ignoreChildren pResponse = Just pResponse
  | ignoreParent cResponse = Just newChildResponse
  | otherwise = Just $ WidgetResult newWidget requests userEvents
  where
    pWidget = _wrNode pResponse
    cWidget = _wrNode cResponse
    requests = _wrRequests pResponse >< _wrRequests cResponse
    userEvents = _wrEvents pResponse >< _wrEvents cResponse
    newWidget = replaceChild pWidget cWidget idx
    newChildResponse = cResponse {
      _wrNode = replaceChild original (_wrNode cResponse) idx
    }

-- | Message Handling
defaultHandleMessage :: ContainerMessageHandler s e
defaultHandleMessage wenv ctx message node = Nothing

handleMessageWrapper
  :: Typeable i
  => Container s e
  -> WidgetEnv s e
  -> Path
  -> i
  -> WidgetNode s e
  -> Maybe (WidgetResult s e)
handleMessageWrapper container wenv target arg node
  | not targetReached && not targetValid = Nothing
  | otherwise = handleSizeReqChange container wenv node Nothing result
  where
    mHandler = containerHandleMessage container
    targetReached = isTargetReached target node
    targetValid = isTargetValid target node
    childIdx = fromJust $ nextTargetStep target node
    children = node ^. L.children
    child = Seq.index children childIdx
    message = widgetHandleMessage (child ^. L.widget) wenv target arg child
    messageResult = updateChild <$> message
    updateChild cr = cr {
      _wrNode = replaceChild node (_wrNode cr) childIdx
    }
    result
      | targetReached = mHandler wenv target arg node
      | otherwise = messageResult

-- | Preferred size
defaultGetSizeReq :: ContainerGetSizeReqHandler s e
defaultGetSizeReq wenv node children = def

updateSizeReq
  :: Container s e
  -> WidgetEnv s e
  -> WidgetNode s e
  -> WidgetNode s e
updateSizeReq container wenv node = newNode where
  psHandler = containerGetSizeReq container
  currState = widgetGetState (node ^. L.widget) wenv
  style = containerGetActiveStyle container wenv node
  children = node ^. L.children
  reqs = psHandler wenv currState node children
  (newReqW, newReqH) = sizeReqAddStyle style reqs
  newNode = node
    & L.info . L.sizeReqW .~ newReqW
    & L.info . L.sizeReqH .~ newReqH

handleSizeReqChange
  :: Container s e
  -> WidgetEnv s e
  -> WidgetNode s e
  -> Maybe SystemEvent
  -> Maybe (WidgetResult s e)
  -> Maybe (WidgetResult s e)
handleSizeReqChange container wenv node evt mResult = result where
  baseResult = fromMaybe (resultWidget node) mResult
  newNode = baseResult ^. L.node
  resizeReq = isResizeResult mResult
  styleChanged = isJust evt && styleStateChanged wenv newNode (fromJust evt)
  result
    | styleChanged || resizeReq = Just $ baseResult
      & L.node .~ updateSizeReq container wenv newNode
    | otherwise = mResult

-- | Resize
defaultResize :: ContainerResizeHandler s e
defaultResize wenv viewport renderArea children node = newSize where
  childrenSizes = Seq.replicate (Seq.length children) def
  newSize = (node, childrenSizes)

resizeWrapper
  :: Container s e
  -> WidgetEnv s e
  -> Rect
  -> Rect
  -> WidgetNode s e
  -> WidgetNode s e
resizeWrapper container wenv viewport renderArea node = newNode where
  resizeRequired = containerResizeRequired container
  useCustomSize = containerUseCustomSize container
  useChildrenSizes = containerUseChildrenSizes container
  handler = containerResize container
  lensVp = L.info . L.viewport
  lensRa = L.info . L.renderArea
  vpChanged = viewport /= node ^. lensVp
  raChanged = renderArea /= node ^. lensRa
  children = node ^. L.children
  (tempNode, assigned) = handler wenv viewport renderArea children node
  resize (child, (vp, ra)) = newChildNode where
    tempChildNode = widgetResize (child ^. L.widget) wenv vp ra child
    cvp = tempChildNode ^. L.info . L.viewport
    cra = tempChildNode ^. L.info . L.renderArea
    icvp = fromMaybe vp (intersectRects vp cvp)
    icra = fromMaybe ra (intersectRects ra cra)
    newChildNode = tempChildNode
      & L.info . L.viewport .~ (if useChildrenSizes then icvp else vp)
      & L.info . L.renderArea .~ (if useChildrenSizes then icra else ra)
  newChildren = resize <$> Seq.zip children assigned
  newVp
    | useCustomSize = tempNode ^. lensVp
    | otherwise = viewport
  newRa
    | useCustomSize = tempNode ^. lensRa
    | otherwise = renderArea
  newNode
    | resizeRequired || vpChanged || raChanged = tempNode
      & L.info . L.viewport .~ newVp
      & L.info . L.renderArea .~ newRa
      & L.children .~ newChildren
    | otherwise = node

-- | Rendering
defaultRender :: ContainerRenderHandler s e
defaultRender renderer wenv node = return ()

renderWrapper
  :: Container s e
  -> Renderer
  -> WidgetEnv s e
  -> WidgetNode s e
  -> IO ()
renderWrapper container renderer wenv node = action where
  style = containerGetActiveStyle container wenv node
  useScissor = containerUseScissor container
  before = containerRender container
  after = containerRenderAfter container
  action = renderContainer renderer wenv style node useScissor before after

renderContainer
  :: Renderer
  -> WidgetEnv s e
  -> StyleState
  -> WidgetNode s e
  -> Bool
  -> ContainerRenderHandler s e
  -> ContainerRenderHandler s e
  -> IO ()
renderContainer renderer wenv style node useScissor renderBefore renderAfter =
  drawInScissor renderer useScissor viewport $
    drawStyledAction renderer renderArea style $ \_ -> do
      renderBefore renderer wenv node

      forM_ children $ \child -> when (isWidgetVisible child viewport) $
        widgetRender (child ^. L.widget) renderer wenv child

      renderAfter renderer wenv node
  where
    children = node ^. L.children
    viewport = node ^. L.info . L.viewport
    renderArea = node ^. L.info . L.renderArea

-- | Event Handling Helpers
ignoreChildren :: WidgetResult s e -> Bool
ignoreChildren result = not (Seq.null ignoreReqs) where
  ignoreReqs = Seq.filter isIgnoreChildrenEvents (_wrRequests result)

ignoreParent :: WidgetResult s e -> Bool
ignoreParent result = not (Seq.null ignoreReqs) where
  ignoreReqs = Seq.filter isIgnoreParentEvents (_wrRequests result)

replaceChild
  :: WidgetNode s e -> WidgetNode s e -> Int -> WidgetNode s e
replaceChild parent child idx = parent & L.children .~ newChildren where
  newChildren = Seq.update idx child (parent ^. L.children)

cascadeCtx
  :: WidgetEnv s e -> WidgetNode s e -> WidgetNode s e -> Int -> WidgetNode s e
cascadeCtx wenv parent child idx = newChild where
  pInfo = parent ^. L.info
  cInfo = child ^. L.info
  parentPath = pInfo ^. L.path
  parentVisible = pInfo ^. L.visible
  parentEnabled = pInfo ^. L.enabled
  newPath = parentPath |> idx
  newChild = child
    & L.info . L.widgetId .~ WidgetId (wenv ^. L.timestamp) newPath
    & L.info . L.path .~ newPath
    & L.info . L.visible .~ (cInfo ^. L.visible && parentVisible)
    & L.info . L.enabled .~ (cInfo ^. L.enabled && parentEnabled)

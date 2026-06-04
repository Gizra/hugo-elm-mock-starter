port module Main exposing (main)

{-| Mock chat app — offline.

The transcript is shown in the Chat column beside a mock sessions sidebar. A
scripted mock in boot.js answers the `sendToOpenAi` port with a stream of
normalized events (`openAiEvent`): streamed text and optional question chips.

-}

import Browser
import Browser.Dom
import Json.Encode as Encode
import OpenAi
import Task
import Types
    exposing
        ( Answer(..)
        , Block(..)
        , Flags
        , Model
        , Msg(..)
        , PanelState(..)
        , Question
        , Role(..)
        , Session
        , Status(..)
        , StreamEvent(..)
        , Turn
        )
import View



-- PORTS


port sendToOpenAi : Encode.Value -> Cmd msg


port openAiEvent : (Encode.Value -> msg) -> Sub msg



-- SCROLL


{-| Keep the chat pinned to the latest message after content is added. -}
scrollChatToBottom : Cmd Msg
scrollChatToBottom =
    Browser.Dom.getViewportOf "chat-scroll"
        |> Task.andThen (\info -> Browser.Dom.setViewportOf "chat-scroll" 0 info.scene.height)
        |> Task.attempt (\_ -> NoOp)


{-| Scroll after any stream event that adds visible chat content. -}
scrollCmdFor : StreamEvent -> Cmd Msg
scrollCmdFor event =
    case event of
        Delta _ ->
            scrollChatToBottom

        Questions _ ->
            scrollChatToBottom

        Done ->
            scrollChatToBottom

        StreamError _ ->
            scrollChatToBottom

        Unknown ->
            Cmd.none



-- INIT


sessionList : List Session
sessionList =
    [ { title = "Welcome chat", when = "Active now" }
    , { title = "Draft idea", when = "Yesterday" }
    , { title = "Untitled", when = "Last week" }
    ]


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { flags = flags
      , transcript = []
      , current = []
      , input = ""
      , status = Idle
      , sessions = Expanded
      , sessionList = sessionList
      , activeSession = 0
      }
    , Cmd.none
    )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InputChanged s ->
            ( { model | input = s }, Cmd.none )

        Send ->
            sendMessage (String.trim model.input) model

        SelectChip value ->
            sendMessage (String.trim value) model

        StreamEvent value ->
            let
                event =
                    OpenAi.decodeEvent value
            in
            ( applyEvent event model, scrollCmdFor event )

        ToggleSessions ->
            ( { model | sessions = toggle model.sessions }, Cmd.none )

        NewChat ->
            ( { model | transcript = [], current = [], input = "", status = Idle, activeSession = 0 }
            , Cmd.none
            )

        SelectSession index ->
            ( { model | activeSession = index }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


sendMessage : String -> Model -> ( Model, Cmd Msg )
sendMessage message model =
    if message == "" || model.status == Streaming then
        ( model, Cmd.none )

    else
        ( { model
            | transcript =
                lockOpenQuestions message model.transcript
                    ++ [ { role = User, blocks = [ TextBlock message ] } ]
            , current = []
            , input = ""
            , status = Streaming
          }
        , Cmd.batch
            [ sendToOpenAi (OpenAi.encodeRequest message)
            , scrollChatToBottom
            ]
        )


{-| Lock the question the user just answered. Any still-`Open` question in the
transcript becomes `Answered`, recording the chosen option when the reply matches
one of its chips (otherwise it was typed). Only the latest question is ever open,
so at most one flips. -}
lockOpenQuestions : String -> List Turn -> List Turn
lockOpenQuestions value turns =
    List.map (\turn -> { turn | blocks = List.map (lockBlock value) turn.blocks }) turns


lockBlock : String -> Block -> Block
lockBlock value block =
    case block of
        QuestionsBlock questions ->
            QuestionsBlock (List.map (lockQuestion value) questions)

        TextBlock _ ->
            block


lockQuestion : String -> Question -> Question
lockQuestion value question =
    case question.answer of
        Open ->
            { question
                | answer =
                    Answered
                        (if List.member value question.options then
                            Just value

                         else
                            Nothing
                        )
            }

        Answered _ ->
            question


applyEvent : StreamEvent -> Model -> Model
applyEvent event model =
    case event of
        Delta chunk ->
            { model | current = appendText chunk model.current }

        Questions qs ->
            { model | current = model.current ++ [ QuestionsBlock qs ] }

        Done ->
            { model
                | transcript = model.transcript ++ commitCurrent model.current
                , current = []
                , status = Idle
            }

        StreamError message ->
            { model
                | transcript =
                    model.transcript
                        ++ commitCurrent model.current
                        ++ [ { role = SystemError, blocks = [ TextBlock message ] } ]
                , current = []
                , status = Idle
            }

        Unknown ->
            model


commitCurrent : List Block -> List Turn
commitCurrent current =
    if List.isEmpty current then
        []

    else
        [ { role = Assistant, blocks = current } ]


appendText : String -> List Block -> List Block
appendText chunk blocks =
    case List.reverse blocks of
        (TextBlock existing) :: rest ->
            List.reverse (TextBlock (existing ++ chunk) :: rest)

        _ ->
            blocks ++ [ TextBlock chunk ]


toggle : PanelState -> PanelState
toggle state =
    case state of
        Expanded ->
            Collapsed

        Collapsed ->
            Expanded



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    openAiEvent StreamEvent



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = View.view
        , subscriptions = subscriptions
        }

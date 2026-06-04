module Types exposing
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

{-| Shared types for the mock chat app.

A sessions sidebar (mock history) sits beside a chat column. The chat sends each
message to a scripted mock (boot.js) over a port and renders the streamed reply,
including optional clickable option chips.

-}

import Json.Encode as Encode



-- FLAGS


type alias Flags =
    { pageTitle : String
    , inputPlaceholder : String
    }



-- CHAT BLOCKS


type Block
    = TextBlock String
    | QuestionsBlock (List Question)


type alias Question =
    { prompt : String
    , options : List String
    , answer : Answer
    }


{-| Whether a question is still awaiting a reply (chips clickable) or has been
answered and locked. `Answered (Just opt)` marks the chip the user picked;
`Answered Nothing` means they typed their own answer instead.
-}
type Answer
    = Open
    | Answered (Maybe String)


type alias Turn =
    { role : Role
    , blocks : List Block
    }


type Role
    = User
    | Assistant
    | SystemError


type Status
    = Idle
    | Streaming



-- SESSIONS (mock history)


type alias Session =
    { title : String
    , when : String
    }


type PanelState
    = Expanded
    | Collapsed



-- MODEL


type alias Model =
    { flags : Flags
    , transcript : List Turn
    , current : List Block
    , input : String
    , status : Status
    , sessions : PanelState
    , sessionList : List Session
    , activeSession : Int
    }



-- MESSAGES


type Msg
    = InputChanged String
    | Send
    | SelectChip String
    | StreamEvent Encode.Value
    | ToggleSessions
    | NewChat
    | SelectSession Int
    | NoOp


{-| Normalized mock stream events decoded from the `openAiEvent` port.
-}
type StreamEvent
    = Delta String
    | Questions (List Question)
    | Done
    | StreamError String
    | Unknown

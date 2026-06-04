module OpenAi exposing
    ( decodeEvent
    , encodeRequest
    )

{-| Mock bridge. Encodes a request for the `sendToOpenAi` port and decodes the
normalized events arriving over `openAiEvent`. No real networking — see boot.js.
-}

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (custom, optional, required)
import Json.Encode as Encode
import Types exposing (Answer(..), Question, StreamEvent(..))



-- REQUEST


encodeRequest : String -> Encode.Value
encodeRequest input =
    Encode.object
        [ ( "input", Encode.string input ) ]



-- EVENT DECODING


decodeEvent : Encode.Value -> StreamEvent
decodeEvent value =
    Decode.decodeValue eventDecoder value
        |> Result.withDefault Unknown


eventDecoder : Decoder StreamEvent
eventDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "delta" ->
                        Decode.map Delta (Decode.field "text" Decode.string)

                    "questions" ->
                        Decode.map Questions (Decode.field "questions" (Decode.list questionDecoder))

                    "done" ->
                        Decode.succeed Done

                    "error" ->
                        Decode.map StreamError (Decode.field "message" (orEmpty Decode.string))

                    _ ->
                        Decode.succeed Unknown
            )


questionDecoder : Decoder Question
questionDecoder =
    Decode.succeed Question
        |> required "prompt" Decode.string
        |> optional "options" (Decode.list Decode.string) []
        |> custom (Decode.map selectedToAnswer (Decode.maybe (Decode.field "selected" Decode.string)))


{-| Live questions arrive with no `selected` key and start `Open`. -}
selectedToAnswer : Maybe String -> Answer
selectedToAnswer selected =
    case selected of
        Just value ->
            Answered (Just value)

        Nothing ->
            Open


orEmpty : Decoder String -> Decoder String
orEmpty decoder =
    Decode.oneOf [ decoder, Decode.succeed "" ]

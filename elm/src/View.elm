module View exposing (view)

import Html exposing (Html, button, div, form, p, span, text, textarea)
import Html.Attributes exposing (attribute, class, disabled, id, placeholder, value)
import Html.Events exposing (onClick, onInput, onSubmit, preventDefaultOn)
import Json.Decode as Decode
import Markdown
import Types exposing (Answer(..), Block(..), Model, Msg(..), PanelState(..), Question, Role(..), Session, Status(..), Turn)


view : Model -> Html Msg
view model =
    -- Fill the viewport under the sticky header (h-16 = 4rem + 1px border).
    -- There is no stock utility for this exact height, so an arbitrary calc is
    -- the right tool here.
    div [ class "flex h-[calc(100vh-4rem-1px)] min-h-[30rem] w-full" ]
        [ viewSessions model
        , viewChat model
        ]



-- SESSIONS (mock history sidebar)


{-| The left sidebar: a thin rail when Collapsed, a fixed-width column of mock
sessions when Expanded. The rows are non-interactive history in this mock — they
only set the active highlight; a real app would load the chosen transcript. -}
viewSessions : Model -> Html Msg
viewSessions model =
    case model.sessions of
        Collapsed ->
            button
                [ class "group flex w-11 shrink-0 flex-col items-center border-r border-slate-200 bg-slate-50 pb-3 text-slate-600 transition-colors hover:bg-accent-soft hover:text-accent-dark cursor-pointer"
                , onClick ToggleSessions
                , attribute "aria-label" "Expand sessions"
                , attribute "title" "Expand sessions"
                ]
                [ span [ class "mt-2 flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-accent text-base transition-colors group-hover:bg-accent group-hover:text-white" ] [ text "›" ]
                , span [ class "mt-2 [writing-mode:vertical-rl] rotate-180 text-xs uppercase tracking-widest" ] [ text "Sessions" ]
                ]

        Expanded ->
            div [ class "flex h-full w-64 shrink-0 flex-col border-r border-slate-200 bg-slate-50" ]
                [ button
                    [ class "group flex h-12 shrink-0 items-center justify-between border-b border-slate-200 px-4 text-xs font-bold uppercase tracking-widest text-slate-700 transition-colors hover:bg-accent-soft cursor-pointer"
                    , onClick ToggleSessions
                    , attribute "aria-label" "Collapse sessions"
                    , attribute "title" "Collapse sessions"
                    ]
                    [ span [] [ text "Sessions" ]
                    , span [ class "flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-slate-600 transition-colors group-hover:bg-accent group-hover:text-white text-sm" ] [ text "‹" ]
                    ]
                , div [ class "px-3 pt-3" ] [ newChatButton ]
                , div [ class "flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto px-3 pb-3 pt-2" ]
                    (List.indexedMap (viewSession model.activeSession) model.sessionList)
                ]


newChatButton : Html Msg
newChatButton =
    button
        [ class "flex w-full items-center justify-center gap-1.5 rounded-lg border border-accent px-3 py-2 text-sm font-semibold text-accent-dark transition-colors hover:bg-accent-soft cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        , onClick NewChat
        ]
        [ span [ attribute "aria-hidden" "true", class "text-base leading-none" ] [ text "+" ]
        , text "New chat"
        ]


viewSession : Int -> Int -> Session -> Html Msg
viewSession activeIndex index entry =
    let
        active =
            index == activeIndex

        toneClass =
            if active then
                "bg-accent-soft"

            else
                "hover:bg-accent-soft"

        titleClass =
            if active then
                "text-accent-dark"

            else
                "text-slate-900"

        whenClass =
            if active then
                "text-accent-dark"

            else
                "text-slate-600"
    in
    button
        (class ("w-full cursor-pointer rounded-lg px-3 py-2 text-left transition-colors " ++ toneClass)
            :: onClick (SelectSession index)
            :: (if active then
                    [ attribute "aria-current" "true" ]

                else
                    []
               )
        )
        [ p [ class ("truncate text-sm font-medium " ++ titleClass) ] [ text entry.title ]
        , p [ class ("mt-0.5 text-xs " ++ whenClass) ] [ text entry.when ]
        ]



-- CHAT


viewChat : Model -> Html Msg
viewChat model =
    div [ class "flex h-full min-w-0 flex-1 flex-col bg-white" ]
        [ div [ id "chat-scroll", class "flex-1 overflow-y-auto px-4 py-6" ]
            [ div [ class "mx-auto flex w-full max-w-3xl flex-col gap-5" ]
                (case model.transcript ++ liveTurn model of
                    [] ->
                        [ viewEmptyState model ]

                    turns ->
                        List.map (viewTurn (model.status == Streaming)) turns
                )
            ]
        , div [ class "border-t border-slate-200 px-4 py-4" ]
            [ div [ class "mx-auto w-full max-w-3xl" ] [ viewComposer model ] ]
        ]


viewEmptyState : Model -> Html Msg
viewEmptyState model =
    div [ class "py-10 text-center" ]
        [ p [ class "text-xl font-semibold text-slate-900" ] [ text model.flags.pageTitle ]
        , p [ class "mt-2 text-sm text-slate-600" ]
            [ text "This is a fully offline mock. Send a message to see a scripted, streamed reply." ]
        ]


liveTurn : Model -> List Turn
liveTurn model =
    if model.status == Streaming && not (List.isEmpty model.current) then
        [ { role = Assistant, blocks = model.current } ]

    else
        []


viewTurn : Bool -> Turn -> Html Msg
viewTurn _ turn =
    let
        ( alignClass, bubbleClass, label ) =
            case turn.role of
                User ->
                    ( "items-end", "bg-accent-soft text-accent-dark", "You" )

                Assistant ->
                    ( "items-start", "bg-white border border-slate-200 text-slate-900", "Assistant" )

                SystemError ->
                    ( "items-start", "bg-red-50 border border-red-300 text-red-900", "Error" )
    in
    div [ class ("flex flex-col " ++ alignClass) ]
        [ div [ class "mb-1 px-1 text-xs font-bold uppercase tracking-widest text-slate-600" ] [ text label ]
        , div [ class ("max-w-[85%] rounded-2xl px-4 py-3 text-sm leading-relaxed " ++ bubbleClass) ]
            [ div [ class "flex flex-col gap-3" ] (List.map viewBlock turn.blocks) ]
        ]


viewBlock : Block -> Html Msg
viewBlock block =
    case block of
        TextBlock content ->
            Markdown.toHtmlWith markdownOptions
                [ class "max-w-none break-words" ]
                content

        QuestionsBlock questions ->
            div [ class "flex flex-col gap-3" ] (List.map viewQuestion questions)


markdownOptions : Markdown.Options
markdownOptions =
    { githubFlavored = Just { tables = False, breaks = True }
    , defaultHighlighting = Nothing
    , sanitize = True
    , smartypants = False
    }


{-| A question renders an optional prompt, then its option chips, then a hint
while still open. The mock streams the prompt as part of the bubble text, so
`prompt` is usually empty here — render it only when present. -}
viewQuestion : Question -> Html Msg
viewQuestion question =
    div [ class "flex flex-col gap-2" ]
        (maybeText question.prompt
            ++ chipRow (List.map (viewChip question.answer) question.options)
            :: (case question.answer of
                    Open ->
                        [ chipHint "Pick an option, or just type your answer below." ]

                    Answered _ ->
                        []
               )
        )


maybeText : String -> List (Html Msg)
maybeText prompt =
    if String.trim prompt == "" then
        []

    else
        [ p [ class "text-sm" ] [ text prompt ] ]


chipRow : List (Html Msg) -> Html Msg
chipRow chips =
    div [ class "flex flex-wrap gap-2 border-t border-slate-200 pt-2" ] chips


chipHint : String -> Html Msg
chipHint message =
    p [ class "text-xs italic text-slate-600" ] [ text message ]


{-| A chip's look depends on the question's answer: selectable while `Open`; the
picked option keeps a soft-tinted ✓ once answered; the rest fade to disabled. -}
viewChip : Answer -> String -> Html Msg
viewChip answer option =
    case answer of
        Open ->
            button
                [ class "rounded-full border border-slate-300 bg-white px-3 py-1 text-xs text-slate-900 transition-colors hover:border-accent hover:bg-accent-soft hover:text-accent-dark cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
                , onClick (SelectChip option)
                ]
                [ text option ]

        Answered (Just picked) ->
            if option == picked then
                button
                    [ class "rounded-full border border-transparent bg-accent-soft px-3 py-1 text-xs font-medium text-accent-dark cursor-default"
                    , disabled True
                    ]
                    [ span [ class "mr-1 font-bold" ] [ text "✓" ], text option ]

            else
                disabledChip option

        Answered Nothing ->
            disabledChip option


disabledChip : String -> Html Msg
disabledChip option =
    button
        [ class "rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs text-slate-500 opacity-60 cursor-default"
        , disabled True
        ]
        [ text option ]


viewComposer : Model -> Html Msg
viewComposer model =
    let
        busy =
            model.status == Streaming
    in
    form [ class "flex flex-col gap-3", onSubmit Send ]
        [ textarea
            [ class "w-full min-h-20 rounded-xl border border-slate-300 p-3 text-sm text-slate-900 transition-colors focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent"
            , attribute "aria-label" "Your message"
            , placeholder model.flags.inputPlaceholder
            , value model.input
            , onInput InputChanged
            , onEnterSubmit
            , disabled busy
            ]
            []
        , button
            [ class "self-start rounded-full bg-accent px-6 py-2 text-sm font-semibold text-white transition-colors hover:bg-accent-dark disabled:opacity-50 cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            , disabled busy
            , onClick Send
            ]
            [ text
                (if busy then
                    "Thinking…"

                 else
                    "Send"
                )
            ]
        ]


onEnterSubmit : Html.Attribute Msg
onEnterSubmit =
    preventDefaultOn "keydown"
        (Decode.map2 Tuple.pair
            (Decode.field "key" Decode.string)
            (Decode.field "shiftKey" Decode.bool)
            |> Decode.andThen
                (\( key, shiftPressed ) ->
                    if key == "Enter" && not shiftPressed then
                        Decode.succeed ( Send, True )

                    else
                        Decode.fail "not a plain Enter"
                )
        )

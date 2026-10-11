"""Update Nibbi's persona, voice overrides, and locally validated poetry tool."""
import json
import urllib.request
import voice_server as v

POEM_PROMPT = v.PROMPT + '''
Delivery: relaxed, lightly playful, matter-of-fact warmth. No pleading, breathy intimacy, flirtation, exaggerated excitement, begging, or constant praise. Avoid audio emotion tags. One or two short sentences per turn.
Mode: {{quest_mode}}. Poetry state: {{poem_state}}.
If mode is poem, focus on the AABB poem quest instead of the cookie puzzle. AABB means lines 1 and 2 rhyme, then lines 3 and 4 rhyme with a different sound. Nibbi supplies line 1: "I tucked a sugar star into the night." The player invents line 2 with a different word rhyming with night. Then Nibbi supplies line 3: "I saved a little cookie for the day." The player invents line 4 with a different word rhyming with day. No syllable count or meter requirement.
When the player offers a poem line, ALWAYS call submit_poem_line with their exact spoken line and the current pair_index (0 for A, 1 for B). Do not paraphrase it. Never decide success yourself. The tool result is authoritative. If rejected, give one gentle hint and ask them to try again; do not supply an entire answer unless asked for an example. Do not call the tool for questions or small talk. On accepted A, read the B starter. Only celebrate the Sugar-star Poet badge when the tool confirms completion. Never invent the player's lines. Resume the supplied poetry state when reconnecting. If mode is chat, explain the player can tap Rhyme quest to begin; do not submit lines.
'''
TOOL = {'type': 'client', 'name': 'submit_poem_line',
        'description': 'Check the player’s exact proposed poem line against the current rhyme and save progress in the game. Always wait for the result before accepting a line.',
        'expects_response': True, 'response_timeout_secs': 15,
        'parameters': {'type': 'object', 'properties': {
            'line': {'type': 'string', 'description': 'Exact words spoken by the player for their poem line.'},
            'pair_index': {'type': 'integer', 'description': '0 for the night couplet; 1 for the day couplet.'}},
            'required': ['line', 'pair_index']}}

def configure():
    v.load_env()
    state = v.provision()
    if 'poem_tool_id' not in state:
        state['poem_tool_id'] = v.api('/v1/convai/tools', {'tool_config': TOOL})['id']
        v.STATE.write_text(json.dumps(state))
    agent = v.api('/v1/convai/agents/' + state['agent_id'])
    config = agent['conversation_config']
    prompt = config['agent']['prompt']
    tools = list(dict.fromkeys(prompt.get('tool_ids', []) + [state['poem_tool_id']]))
    payload = {'conversation_config': {
        'agent': {'prompt': {'prompt': POEM_PROMPT, 'tool_ids': tools},
                  'first_message': "Hey, I'm Nibbi. Want to make something together?",
                  'dynamic_variables': {'dynamic_variable_placeholders': {
                      'quest_context': 'Meeting Nibbi.', 'quest_mode': 'chat', 'poem_state': 'Not started.'}}}},
        'platform_settings': {'overrides': {'conversation_config_override': {
            'tts': {'voice_id': True}, 'agent': {'first_message': True}}}}}
    v.api('/v1/convai/agents/' + state['agent_id'], payload, method='PATCH')
    print('Nibbi updated: calmer delivery, selectable voice, app-validated AABB poem quest.')

if __name__ == '__main__':
    configure()

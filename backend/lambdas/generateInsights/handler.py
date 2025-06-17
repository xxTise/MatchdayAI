import os
import json
import boto3
from datetime import datetime

# Env vars
TABLE_NAME   = os.environ["CACHE_TABLE"]
MODEL_ID     = os.environ["BEDROCK_MODEL_ID"]

# AWS clients
dynamo  = boto3.resource("dynamodb")
table   = dynamo.Table(TABLE_NAME)
bedrock = boto3.client("bedrock-runtime")

def create_prompt(fixture):
    home  = fixture["teams"]["home"]["name"]
    away  = fixture["teams"]["away"]["name"]
    score = f'{fixture["goals"]["home"]}-{fixture["goals"]["away"]}'
    events = fixture.get("events", [])
    events_str = "; ".join(
        f"{e['elapsed']}' {e['team']['name']} {e['player']['name']} {e['type']}"
        for e in events
    ) or "No major events recorded."
    return (
        f"Summarize the soccer match between {home} and {away} "
        f"which ended {score}. Key events: {events_str}. "
        "Provide a concise, engaging summary."
    )

def lambda_handler(event, context):
    # Optionally process a single fixture_id
    fixture_id = event.get("fixture_id")

    if fixture_id:
        resp = table.get_item(Key={"fixture_id": fixture_id})
        items = [resp["Item"]] if "Item" in resp else []
    else:
        resp  = table.scan()
        items = resp.get("Items", [])

    outputs = []
    for item in items:
        data    = item["data"]
        prompt  = create_prompt(data)

        # Invoke Bedrock model
        response = bedrock.invoke_model(
            modelId=MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps({"input": prompt})
        )
        body      = json.loads(response["body"])
        summary   = body.get("completion") or body

        # Persist summary
        table.update_item(
            Key={"fixture_id": item["fixture_id"]},
            UpdateExpression="SET insights = :i, insights_at = :t",
            ExpressionAttributeValues={
                ":i": summary,
                ":t": datetime.utcnow().isoformat()
            }
        )
        outputs.append({"fixture_id": item["fixture_id"], "insights": summary})

    return {
        "statusCode": 200,
        "body": json.dumps(outputs)
    }

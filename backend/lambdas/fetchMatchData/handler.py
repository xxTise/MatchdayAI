import json
import os
import urllib.request

API_URL = "https://v3.football.api-sports.io/fixtures?live=all"
API_KEY = os.environ["API_FOOTBALL_KEY"]

def lambda_handler(event, context):
    req = urllib.request.Request(
        API_URL,
        headers={ "x-apisports-key": API_KEY }
    )
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            data = json.loads(body)
        return {
            "statusCode": 200,
            "body": json.dumps(data)
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({ "error": str(e) })
        }

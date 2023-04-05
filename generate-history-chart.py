import pygit2
import json
import datetime
import matplotlib.pyplot as plt
import pytz

def get_last_commit_before_timestamp(repo, file_path, timestamp):
    for commit in repo.walk(repo.head.target, pygit2.GIT_SORT_TIME):
        if commit.commit_time < timestamp:
            if file_path in commit.tree:
                blob = repo[commit.tree[file_path].id]
                content = blob.data.decode('utf-8')
                return json.loads(content)
    return None

repo_path = '.'
config = [
    {"name": "bahnhofsplatz", "displayName": "Bahnhofsplatz", "filePath": "history-data/history--bahnhofsplatz.json"},
    {"name": "hausen-1", "displayName": "Hausen 1", "filePath": "history-data/history--hausen-1.json"},
    {"name": "hausen-2", "displayName": "Hausen 2", "filePath": "history-data/history--hausen-2.json"}
]

repo = pygit2.Repository(repo_path)

now_utc = datetime.datetime.now(pytz.utc)
now = now_utc.astimezone(pytz.timezone('Europe/Berlin'))
yesterday = now - datetime.timedelta(days=1)
yesterday_start = datetime.datetime.combine(yesterday, datetime.time.min).astimezone(pytz.utc)
yesterday_end = datetime.datetime.combine(yesterday, datetime.time.max).astimezone(pytz.utc) - datetime.timedelta(microseconds=1)

dateString = yesterday.strftime("%Y-%m-%d")

berlin_tz = pytz.timezone('Europe/Berlin')

for cfg in config:
    name = cfg["name"]
    displayName = cfg["displayName"]
    file_path = cfg["filePath"]

    data = {"availableChargePoints": {}}

    prev_day_value = get_last_commit_before_timestamp(repo, file_path, yesterday_start.timestamp())
    if prev_day_value is not None:
        data["availableChargePoints"] = {hour.astimezone(berlin_tz): [prev_day_value["availableChargePoints"]] for hour in [yesterday_start + datetime.timedelta(hours=i) for i in range(24)]}

    for commit in repo.walk(repo.head.target, pygit2.GIT_SORT_TIME):
        if commit.commit_time < yesterday_start.timestamp():
            break
        if (yesterday_start.timestamp() <= commit.commit_time <= yesterday_end.timestamp()) and file_path in commit.tree:
            blob = repo[commit.tree[file_path].id]
            content = blob.data.decode('utf-8')
            values = json.loads(content)
            for key, value in values.items():
                if key not in data:
                    data[key] = {}
                timestamp = datetime.datetime.fromtimestamp(commit.commit_time, berlin_tz)
                hour = timestamp.replace(minute=0, second=0, microsecond=0)
                data[key][hour] = [value]

    prev_value = prev_day_value["availableChargePoints"] if prev_day_value is not None else 0
    for hour in [yesterday_start + datetime.timedelta(hours=i) for i in range(24)]:
        hour_berlin = hour.astimezone(berlin_tz)
        if hour_berlin not in data["availableChargePoints"]:
            data["availableChargePoints"][hour_berlin] = [prev_value]
        else:
            prev_value = int(round(sum(data["availableChargePoints"][hour_berlin]) / len(data["availableChargePoints"][hour_berlin])))

    x = []
    y = []

    for hour in sorted(data['availableChargePoints']):
        values = data['availableChargePoints'][hour]
        if values:
            average = int(round(sum(values) / len(values)))
        else:
            average = 0
        x.append(hour.strftime("%H:%M"))
        y.append(average)

    plt.bar(x, y, align='center')
    plt.xlabel('Hour')
    plt.ylabel('Available Charge Points')
    plt.title('Charge Point Availability "' + displayName + '" on ' + dateString)

    for i, v in enumerate(y):
        plt.text(i, v+0.02, str(v), color='black', ha='center')

    plt.yticks(range(3))
    plt.xticks(rotation=90)
    plt.savefig('history-charts/' + name + '/' + dateString + '.png')
    plt.clf()

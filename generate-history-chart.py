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

berlin_tz = pytz.timezone('Europe/Berlin')
now = datetime.datetime.now(berlin_tz)
yesterday = now - datetime.timedelta(days=1)

berlin_tz = pytz.timezone('Europe/Berlin')

yesterday_start_berlin = datetime.datetime.combine(yesterday, datetime.time.min).astimezone(berlin_tz)
yesterday_end_berlin = datetime.datetime.combine(yesterday, datetime.time.max).astimezone(berlin_tz) - datetime.timedelta(microseconds=1)
yesterday_start = yesterday_start_berlin.astimezone(pytz.utc)
yesterday_end = yesterday_end_berlin.astimezone(pytz.utc)

dateString = yesterday.strftime("%Y-%m-%d")

berlin_tz = pytz.timezone('Europe/Berlin')

for cfg in config:
    name = cfg["name"]
    displayName = cfg["displayName"]
    file_path = cfg["filePath"]

    prev_day_value = get_last_commit_before_timestamp(repo, file_path, yesterday_start.timestamp())

    if prev_day_value is not None:
        prev_day_available_charge_points = prev_day_value["availableChargePoints"]
    else:
        prev_day_available_charge_points = 0

    timestamps = [yesterday_start_berlin]
    y = [prev_day_available_charge_points]

    prev_value = prev_day_available_charge_points
    for commit in repo.walk(repo.head.target, pygit2.GIT_SORT_TIME):
        if commit.commit_time < yesterday_start.timestamp():
            break
        if (yesterday_start.timestamp() <= commit.commit_time <= yesterday_end.timestamp()) and file_path in commit.tree:
            blob = repo[commit.tree[file_path].id]
            content = blob.data.decode('utf-8')
            values = json.loads(content)
            timestamp = datetime.datetime.fromtimestamp(commit.commit_time, berlin_tz)

            if "availableChargePoints" in values and values["availableChargePoints"] != prev_value:
                timestamps.append(timestamp)
                y.append(values["availableChargePoints"])
                prev_value = values["availableChargePoints"]

    timestamps_y_values = list(zip(timestamps, y))
    timestamps_y_values.append((yesterday_end_berlin, prev_value))
    timestamps_y_values.sort()

    timestamps, y = zip(*timestamps_y_values)

    x_labels = [t.strftime('%H:%M') for t in timestamps]

    plt.bar(x_labels, y, align='center')
    plt.xlabel('Time')
    plt.ylabel('Available Charge Points')
    plt.title('Charge Point Availability "' + displayName + '" on ' + dateString)

    for i, v in enumerate(y):
        plt.text(i, v+0.02, str(v), color='black', ha='center')

    plt.yticks(range(3))
    plt.xticks(rotation=90)
    plt.savefig('history-charts/' + name + '/' + dateString + '.png')
    plt.clf()


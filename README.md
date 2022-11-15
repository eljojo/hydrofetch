# Hydrofetch

Scrape your favourite hydro provider. Due to reasons, it may return yesterday's consumption at this time.

```
$> docker run -it -e HYDRO_USER=my@email.com -e HYDRO_PASS=hunter2 ghcr.io/eljojo/hydrofetch:latest hydrofetch
I, [2022-11-14T04:52:39.304045 #1]  INFO -- : logging into hydro
D, [2022-11-14T04:52:42.625000 #1] DEBUG -- : sending username and password
D, [2022-11-14T04:52:43.080183 #1] DEBUG -- : waiting: MyAccount - Hydro
I, [2022-11-14T04:52:47.002654 #1]  INFO -- : fetching api session token from hydro
I, [2022-11-14T04:52:47.188416 #1]  INFO -- : fetching api_session using api_token
I, [2022-11-14T04:52:48.926413 #1]  INFO -- : fetching report
{
  "intervalStart": 1668312000,
  "intervalEnd": 1668315599,
  "intervalStartDate": "2022-11-12 23:00:00",
  "intervalEndDate": "2022-11-12 23:59:59",
  "cost": 0.1,
  "consumption": 1.36,
  "temperature": 5,
  "tariff": "Off-Peak"
}
```

Run it as a server and get an API
```
$> docker run -it -p 80:8080 -e APP_ENV=production -e HYDRO_USER=my@email.com -e HYDRO_PASS=hunter2 ghcr.io/eljojo/hydrofetch:latest hydrofetch server
== Sinatra (v3.0.2) has taken the stage on 8080 for production with backup from Puma
Puma starting in single mode...
* Puma version: 6.0.0 (ruby 3.1.2-p20) ("Sunflower")
*  Min threads: 0
*  Max threads: 5
*  Environment: production
*          PID: 1
* Listening on http://0.0.0.0:8080
Use Ctrl-C to stop
I, [2022-11-14T04:56:39.355321 #1]  INFO -- : logging into hydro
D, [2022-11-14T04:56:42.752807 #1] DEBUG -- : sending username and password
D, [2022-11-14T04:56:43.220369 #1] DEBUG -- : waiting: MyAccount - Hydro
I, [2022-11-14T04:56:46.858511 #1]  INFO -- : fetching api session token from hydro
I, [2022-11-14T04:56:47.013331 #1]  INFO -- : fetching api_session using api_token
I, [2022-11-14T04:56:48.955995 #1]  INFO -- : fetching report
172.17.0.1 - - [14/Nov/2022:04:56:49 +0000] "GET / HTTP/1.1" 200 234 10.4849
```

The API also returns a field called `consumed_kwh_proportional` which slowly goes up throught the hour, maxing out five minutes before the end of each hour. It's [perfect](https://developers.home-assistant.io/blog/2021/08/16/state_class_total/) to use with Home Assistant and the [REST sensor](https://www.home-assistant.io/integrations/sensor.rest/) for [Energy Monitoring](https://www.home-assistant.io/blog/2021/08/04/home-energy-management/):

```yaml
sensor:
  - platform: rest
    name: hydroottawa
    device_class: energy
    state_class: total_increasing
    unit_of_measurement: kWh
    json_attributes:
      - tariff_cost
      - consumed_kwh
      - tariff_name
      - interval_cost
    resource: https://hydrofetch.myserver
    value_template: "{{ value_json.consumed_kwh_proportional }}"
  - platform: template
    sensors:
      hydroottawa_tariff_cost:
        friendly_name: "HydroOttawa: Tariff"
        value_template: "{{ state_attr('sensor.hydroottawa', 'tariff_cost') }}"
        device_class: monetary
        unit_of_measurement: CAD/kWh
```

## Development

- `nix-shell --run zsh` to load dev shell with ruby and stuff
- `nix/bundle` to install gems


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eljojo/hydrofetch. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/eljojo/hydrofetch/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Hydrofetch project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/eljojo/hydrofetch/blob/main/CODE_OF_CONDUCT.md).

# CIRCLE-CI analyze intermittent failures script

Ruby script to analyze intermittent rspec failures based on CircleCI data.

## How it works

1. Downloads all CI builds for given range
2. Filters `rspec` builds which were not cancelled
3. Filters multiple builds for same commit which run several times and were finally successfully `fixed`
4. Downloads logs for failed builds per container.
5. Filters & groups per individual specs

## Setup

1. Create CircleCI api token and add to `ci_secret_token.txt` in project root folder
2. Update build start and end numbers inside script
3. Adjust filtering patterns in the script if needed

## Running

Just

```
./analyze_builds.rb
```

Note: Loading builds data for the first time can take several hours. So, try small quantities first.

## Output

```
0 0 0 1 0 spec/acceptance/xxx...rb:42 # Spec failure message
2 0 2 1 3 spec/features/xxx...rb:4 # Spec failure message
...
```

where `2 0 2 1 3` is quantity of intermittent failures for each week.

* Current week: `3`
* Prev week: `1`
* Week-2: `2`
* etc.

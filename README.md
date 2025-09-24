# timeout-snooze

This package provides a `Timeout` that can be snoozed, allowing you to give extra time to the action.

The primary purpose of this package is to support a timeout for `hspec` tests that can be reset during flaky test detection (where we rerun a test case, and if it succeeds the second time, we call it a flake).
When we initially implemented flaky test detection, we simply doubled our timeout, but this is unnecessarily lax, and makes true problems take twice as long to be detected.

The system is based on the `stm-delay` package, which leverages the GHC event manager API.
This package incurs a single thread overhead for `race` for the timeout.

## Comparison with Existing Implementations

### `System.Timeout`

This module lives in `base` and gives you an efficient function:

```haskell
timeout :: Int -> IO a -> IO (Maybe a)
```

However, it is not possible to extend the timeout.

### [`time-manager`](https://www.stackage.org/haddock/lts-24.12/time-manager-0.2.3/System-TimeManager.html) `System.TimeManager`

This implementation is used in warp to provide slow loris protection.
This is a bit heavier duty.
Instead of forking a thread for each action, a `Manager` is used to store a list of timeout actions.
The `Manager` thread wakes every `N` microseconds, looks through the list of actions, and toggles them to `Inactive` if they are `Active`.
The next `N` microseconds, if an action is still `Inactive`, then it is canceled.

The `Handle` can be `tickle`d to reset the state to `Active`, or `pause` can be used to pause the time.
However, the actual time delay of the action is set to the `Manager`, which means that different tests cannot have different timeouts.
We have some known long running tests, and so we need configurable timeouts in our implementation.
For this reason, `time-manager` is not suitable.

### [`timer-wheel`](https://hackage.haskell.org/package/timer-wheel)

`TimerWheel` allows us to create timers and is efficiently designed.
Timers can be set arbitrarily far in the future, so we do get customizable timeouts.
However, there doesn't appear to be a way to reset the timer, so this does not satisfy our needs.

Additionally, it relies on a `ki` library which has an opinionated notion of how concurrency is done.
The assumptions made in `ki` are invalid in `hspec`, which renders it useless to me.

### [`async-timer`](https://hackage.haskell.org/package/async-timer)

The package `async-timer` allows for customizable `TimeoutConf`, and the given `Timer` can be reset.
The actual timer loop is implemented using `Control.Concurrent.Async.race`.

I believe this could be used for my purpose.
We would write:

```haskell
timeoutKillThread :: Int -> (IO () -> IO a) -> IO (Maybe a)
timeoutKillThread micros action = do
    let conf = setInterval micros defaultConf
    withAsyncTimer conf \timer -> do
        ea <- race (wait timer) (action (reset timer))
        case ea of
            Left e -> pure Nothing
            Right a -> pure (Just a)
```

Now, this is a bit unsatisfying to me.
I don't think I am so performance sensitive here that I want to go the `time-manager` approach with a global registered reaper thread instead of `N` reaper threads - the complexity there is challenging, particularly since extending that design with custom timeouts would be tricky.
But this implementation here requires us to fork *many* threads:

1. `withAsyncTimer` forks a thread for `timerLoop` in a `withAsync`
2. We fork a thread with `race` for `wait timer`
3. `timerLoop` does `race`, forking an additional thread for the sleep.

That's `3N` extra threads.
That's quite a lot of overhead.

### [`stm-delay`](https://hackage.haskell.org/package/stm-delay)

This package uses the GHC event manager, which makes it the most efficient option: no threads are forked for the timer, just a registered action.

My primary reservation with the library is age.
It was initially written in 2012, updated in 2014, but it did receive a patch in 2024.

This allows us to write:

```haskell
timeoutKillThread :: Int -> (IO () -> IO a) -> IO (Maybe a)
timeoutKillThread micros action = do
    delay <- newDelay micros 
    let bump = updateDelay delay micros
    ea <- race (atomically (waitDelay delay)) (action bump)
    case ea of
        Left () -> pure Nothing
        Right a -> pure (Just a)
```

We incur an extra thread for `race`.
We could avoid that, but it would essentially require us re-implementing the `stm-delay` but instead of `writeTVar` we'd be doing `killThread` - which the docs for [`TimeoutCallback`](https://www.stackage.org/haddock/lts-24.12/base-4.20.2.0/GHC-Event.html#t:TimeoutCallback) explicitly warn against.

I'm pretty pleased with a single thread overhead.

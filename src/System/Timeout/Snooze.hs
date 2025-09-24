-- | This module provides a 'Timeout' that can be remotely reset, allowing
-- the timeout to be extended.
module System.Timeout.Snooze
    ( timeoutWithSnooze
    , SnoozeHandle
    , snooze
    ) where

import Control.Concurrent.STM.Delay
import UnliftIO

-- | A 'SnoozeHandle' is a handle that allows you to reset the timeout for
-- the given action.
--
-- @since 0.1.0.0
newtype SnoozeHandle = SnoozeHandle (IO ())

-- | Reset the timeout to the original delay given in 'timeoutWithSnooze'.
--
-- @since 0.1.0.0
snooze :: (MonadIO m) => SnoozeHandle -> m ()
snooze (SnoozeHandle action) = liftIO action

-- | Like "System.Timeout".'System.Timeout.timeout', but also passes
-- a 'SnoozeHandle' into the callback. This 'SnoozeHandle' can be 'snooze'd to reset
-- the timeout to the original delay.
--
-- @since 0.1.0.0
timeoutWithSnooze
    :: (MonadUnliftIO m) => Int -> (SnoozeHandle -> m a) -> m (Maybe a)
timeoutWithSnooze microseconds action = do
    delay <- liftIO $ newDelay microseconds
    let
        bump = liftIO $ updateDelay delay microseconds
    ea <- race (liftIO (atomically (waitDelay delay))) (action (SnoozeHandle bump))
    case ea of
        Left () -> pure Nothing
        Right a -> pure (Just a)

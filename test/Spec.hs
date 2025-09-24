import Control.Concurrent
import System.Timeout.Snooze
import Test.Hspec

main :: IO ()
main = hspec $ do
    describe "System.Timeout.Snooze" $ do
        it "times out a long running action" $ do
            munit <- timeoutWithSnooze 1000 $ \_ -> do
                threadDelay 2000
            munit `shouldBe` Nothing

        it "passes if you're fast enough" $ do
            munit <- timeoutWithSnooze 10000 $ \_ -> do
                threadDelay 1000
            munit `shouldBe` Just ()

        it "allows you to snooze" $ do
            munit <- timeoutWithSnooze 10000 $ \sn -> do
                threadDelay 9000
                snooze sn
                threadDelay 9000
            munit `shouldBe` Just ()
